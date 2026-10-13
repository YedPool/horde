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
# WHAT IT SAYS: FIXED WORDS, AND NOTHING FROM OUTSIDE (safety review of the first build, item 9). The
# first version told the trouble's own sentence, and that sentence carries reasons - up to 600
# characters of the revision tool's error output, of what the FETCHED code printed when its check
# failed, of local paths. A notice is read by an AI session; text that a remote repository's author
# can shape must never be put in front of one as if Horde had said it. So a notice is told as the
# service's name - a name this machine's owner chose, held to a pattern - and one fixed sentence for
# each KIND of trouble, chosen from the closed list below by the kind alone. The reason stays where
# a person reads it: horde services status, and the journal.
#
# A TEST'S HOME TELLS NOBODY. A Horde home under the temp folder is a suite's; a tell from one is
# refused before any messenger or any session's record is looked for, whatever its settings say. The
# setting tellWarchief is one guard and this is the other, because the seat is found in a store whose
# place does not follow the Horde home (item 7).
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

# One fixed sentence a kind of trouble (core/Services.ps1 names the kinds: the part of a trouble's key
# before any revision). A kind that is not here is told as the last line says, never by its own text.
$script:HordeServiceTellSentences = [ordered]@{
    "failing"          = "it keeps failing to stay up; it is still being tried, slowly"
    "ended-itself"     = "it ended itself on purpose and is held; it is not started again until a person lets it go"
    "rolled-back"      = "an update did not come up and was rolled back; that revision is not tried again"
    "retreat"          = "an update did not come up and could NOT be rolled back; its checkout needs a person"
    "half-moved"       = "its checkout was left part way through a move; nothing is started from it until a person has put it right"
    "checkout"         = "its checkout cannot take an update as it is; nothing was touched"
    "verify"           = "a new revision failed its check; the old one keeps running"
    "apply"            = "a new revision could not be put in place; the old one keeps running"
    "stuck"            = "its process should have ended and could not be ended"
    "start-unrecorded" = "a start of it was interrupted and it keeps no heartbeat, so whether it is running cannot be told"
}
$script:HordeServiceTellNamePattern = '\A[a-z][a-z0-9-]{0,39}\z'

function Format-HordeServiceNoticeBody {
    # PURE. The words of one notice (header): the service's name and fixed sentences, by the notice's
    # kind and its what - never its text. A name that is not a service name is not repeated either.
    param([Parameter(Mandatory = $true)]$Notice)
    $service = "a service"
    $named = $Notice.PSObject.Properties["service"]
    if ($null -ne $named -and "" + $named.Value -cmatch $script:HordeServiceTellNamePattern) { $service = "service " + $named.Value }
    if ("" + $Notice.kind -ceq "recovered") { return ("HORDE SERVICES - recovered`n" + $service + ": what it was told about is over, and it is running`nSee it with: horde services status") }
    $said = New-Object System.Collections.ArrayList
    $what = $Notice.PSObject.Properties["what"]
    if ($null -ne $what) { foreach ($w in @(("" + $what.Value) -split ",")) { if ($script:HordeServiceTellSentences.Contains($w) -and -not $said.Contains($script:HordeServiceTellSentences[$w])) { [void]$said.Add($script:HordeServiceTellSentences[$w]) } } }
    if ($said.Count -eq 0) { [void]$said.Add("it needs a person") }
    return ("HORDE SERVICES - needs attention`n" + $service + ": " + ($said -join "; ") + "`nSee it with: horde services status")
}

function Test-HordeServiceHomeIsATests {
    # Is -HordeHome under the temp folder (header, A TEST'S HOME TELLS NOBODY)? Compared resolved and
    # without case. A home that cannot be resolved is treated as a test's: telling nobody is the
    # safe mistake.
    param([string]$HordeHome, [string]$TempRoot = "")
    if ($TempRoot -eq "") { $TempRoot = [System.IO.Path]::GetTempPath() }
    try {
        $root = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd('\', '/') + '\'
        $full = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\', '/') + '\'
        return [bool]$full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $true }
}

function Send-HordeServiceNotices {
    # Post each notice to the warchief's session: { told; problem }. told is the ids a messenger took;
    # problem is why the rest were not, in one sentence, or "". Never throws for the far end.
    # -Seat is for a suite that hands in its own.
    param([Parameter(Mandatory = $true)]$Notices, [string]$HordeHome = "", [Parameter(Mandatory = $true)]$Policy, [scriptblock]$Seat = $null, [string]$TempRoot = "")
    $told = New-Object System.Collections.ArrayList
    $done = { param([string]$Problem) return [pscustomobject]@{ told = [string[]]@($told.ToArray()); problem = $Problem } }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    # BEFORE ANYTHING IS LOOKED FOR: a test's home tells nobody (header).
    if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return (& $done "this Horde home is under the temp folder, so it is a test's: nobody is told") }
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
