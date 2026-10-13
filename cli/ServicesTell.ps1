# cli/ServicesTell - how the supervisor of services tells the warchief's session that a service is in
# trouble, or out of it: through the messenger port, never by typing into anything.
#
# WHY A MESSENGER (messengers/Port.ps1). A notice typed into a session's input box is the defect
# family the fleet's mail was built to end - it splices into whatever is being typed there. So the
# notice is a message, posted through whichever loaded messenger offers body.untyped and
# idempotent.post: the first keeps it out of any input box, the second makes a notice posted again
# under the same id - after a pass that could not record it was sent - one notice, not two.
#
# WHO IT GOES TO. The session holding the role of warchief (core/SessionSeat.ps1), as the decisions
# doorbell's notices do (decisions/Notify.ps1). No session, or two that both claim the role, is nobody
# to tell: nothing is posted, the reason is returned, and the notices wait in the services' state
# files for the next pass (cli/ServicesTend.ps1, Send-HordeServicePending).
#
# WHAT IT SAYS. One line of what is wrong, already cleared of anything secret-shaped
# (core/ServicesFiles.ps1, Protect-HordeServiceText), and the command that shows the rest.
#
# THE CALLER LOADS THE PORT. messengers/Port.ps1, every messenger's file, core/SessionSeat.ps1 and
# core/Device.ps1 must have been dot-sourced in the scope this is called from, so the blocks a
# messenger registered can still see its helpers (cli/commands/services.ps1 does it in the one block
# that calls this, once a process).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeServiceTellNeeds = @("body.untyped", "idempotent.post")
$script:HordeServiceTellRole = "warchief"
# Who a notice is from: the supervisor is no session, so it names itself in a session id's shape, and
# wears the label of the setting fromLabel (a messenger may hold a message whose sender it cannot place).
$script:HordeServiceTellFrom = "horde-services"
# How long a notice may wait in a mailbox: the link's most, 7 days (messengers/Port.ps1).
$script:HordeServiceTellTtlSeconds = 604800
$script:HordeServiceTellStages = @("accepted", "handed-over", "seen")

function Format-HordeServiceNoticeBody {
    # PURE. The words of one notice.
    param([Parameter(Mandatory = $true)]$Notice)
    $first = $(if ("" + $Notice.kind -ceq "recovered") { "HORDE SERVICES - recovered" } else { "HORDE SERVICES - needs attention" })
    return ($first + "`n" + $Notice.text + "`n" + "See it with: horde services status")
}

function Send-HordeServiceNotices {
    # Post each notice to the warchief's session: { told; problem }. told is the ids a messenger took;
    # problem is why the rest were not, in one sentence, or "". Never throws for the far end.
    # -Seat is for a suite that hands in its own.
    param([Parameter(Mandatory = $true)]$Notices, [string]$HordeHome = "", [Parameter(Mandatory = $true)]$Policy, [scriptblock]$Seat = $null)
    $told = New-Object System.Collections.ArrayList
    $done = { param([string]$Problem) return [pscustomobject]@{ told = [string[]]@($told.ToArray()); problem = $Problem } }
    $found = Find-HordeMessenger -Require $script:HordeServiceTellNeeds
    if ($found.state -ceq "absent") { return (& $done ("no messenger on this machine can deliver to a session (" + $found.reason + ")")) }
    if ($found.state -cne "known") { return (& $done ("no messenger was chosen: " + $found.reason)) }
    $messenger = $found.value
    if ($null -eq $Seat) { $Seat = { return (Get-HordeRoleSeat -Role $script:HordeServiceTellRole) } }
    $where = $null
    try { $where = @(& $Seat) | Select-Object -Last 1 } catch { $where = New-HordeUnknown -Reason "the seat could not be read" -ErrorRecord $_ }
    if ($null -eq $where -or "$($where.state)" -ceq "absent") { return (& $done ("no session holds the role of " + $script:HordeServiceTellRole + ", so there is nobody to tell")) }
    if ("$($where.state)" -cne "known") { return (& $done ("the " + $script:HordeServiceTellRole + "'s session cannot be told: " + $where.reason)) }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return (& $done ("this machine's device id could not be had: " + $_.Exception.Message)) }
    $problem = ""
    foreach ($n in @($Notices)) {
        $message = [pscustomobject]@{
            messageId = "" + $n.id; sessionId = "" + $where.value.sessionId
            from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeServiceTellFrom; label = "" + $Policy.fromLabel }
            body = (Format-HordeServiceNoticeBody -Notice $n); ttlSeconds = $script:HordeServiceTellTtlSeconds
        }
        $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
        if ($posted.state -ceq "known" -and $script:HordeServiceTellStages -ccontains "$($posted.value.stage)") { [void]$told.Add("" + $n.id); continue }
        if ($posted.state -ceq "known") { $problem = "messenger " + $messenger.name + " answered " + $posted.value.stage }
        else { $problem = "messenger " + $messenger.name + " did not take it: " + $posted.reason }
    }
    return (& $done $problem)
}
