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
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "Device.ps1")
# The port the mails are posted through. Like core/Wake.ps1 with the waker port, this core file loads a
# port that lives beside its adapters, because it calls it.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "messengers\Port.ps1")

# What these senders need of a messenger (the header).
$script:HordeWakeMailMessengerNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
# The stages at which a mail is in the session's mailbox or further (messengers/Port.ps1, THE STAGES).
$script:HordeWakeMailStages = @("accepted", "handed-over", "seen")

function Send-HordeWakeMail {
    # Post one mail ({ to; messageId; body }) to its session. A tristate answer: known { messageId;
    # stage; messenger } when the mail is in the session's mailbox or further, and unknown with the
    # reason for everything else - no messenger that offers what is needed, two that do, no device id,
    # a mail the port refused, a messenger that held it. NOTHING IS CLAIMED THAT DID NOT HAPPEN.
    # -Messenger is for a caller that holds one - a test hands in the in-process one - and is found
    # through the port when it is not given.
    param([Parameter(Mandatory = $true)]$Mail, [Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$Label, [int]$TtlSeconds = 86400, $Messenger = $null, [string]$HordeHome = (Get-HordeHome))
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
    $posted = Send-HordeMessengerMessage -Messenger $through -Message $message
    if ($posted.state -cne "known") { return $posted }
    if ($script:HordeWakeMailStages -cnotcontains "$($posted.value.stage)") {
        $why = ""
        $p = $posted.value.PSObject.Properties["reason"]
        if ($null -ne $p) { $why = ": " + $p.Value }
        return (New-HordeUnknown -Reason ("the messenger answered " + $posted.value.stage + $why))
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = "$($Mail.messageId)"; stage = "$($posted.value.stage)"; messenger = "$($through.name)" }) -ObservedAt $posted.observedAt)
}
