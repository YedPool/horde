# cli/RelayRunTell - how the relay runner tells the warchief's session that the relay is REFUSING what
# this machine sends to the founder's phone because a mailbox, or the account, is full.
#
# WHY IT EXISTS (2026-10-13). The hosted relay refuses every put into a mailbox that holds its most
# (2,000 envelopes or 20 MiB, status 507) and into an account over its storage. The phone's mailbox is
# acked by nobody, so until its senders trimmed their own streams (relays/Port.ps1, A SENDER TRIMS ITS
# OWN STREAM) it was days from that, and a refusal was one more failed turn: the run backed off, tried
# again, and said so in a log nobody was reading - for ever, while NOTHING reached the founder's phone
# and nothing told anyone. A phone that has gone quiet looks exactly like a quiet day. So the run now
# says it plainly in its own log (cli/RelayRun.ps1) and tells the warchief ONCE.
#
# THE PATH IS THE ONE THE OTHER BELLS USE, not a new one: a message through the messenger port
# (messengers/Port.ps1) to the session that holds the role of warchief (core/SessionSeat.ps1), exactly
# as the decisions doorbell (decisions/Notify.ps1) and the supervisor of services (cli/ServicesTell.ps1)
# tell it. A messenger must offer body.untyped - a notice typed into a session's input box splices into
# whatever is being typed there - and idempotent.post, so the same notice posted again is one notice.
#
# ONCE. A refusal's notice is named by what it is about - this home, the mailbox, the UTC day
# (core/TextUuid.ps1) - so a run that is restarted while the mailbox is still full (the supervisor
# restarts it at every update) posts the SAME notice, which an idempotent messenger keeps as one. Within
# a run, a mailbox the warchief has been told of is not told of again until a put into it has been
# taken and it has filled once more. A notice that could not be posted - no messenger, no warchief's
# seat - is tried again on a later turn, and why is said once in the log: nothing is claimed as told
# that was not.
#
# WHAT IT SAYS: FIXED WORDS, AND NOTHING OF THE RELAY'S. The relay is untrusted, and its reason for a
# refusal is its own text; a notice is read by an AI session, and text an outside party can shape must
# never be put in front of one as if Horde had said it (cli/ServicesTell.ps1, the same rule, from the
# safety review of the first services build). So the notice holds a fixed sentence and the mailbox's
# name - which this machine made from its own horde's name, held to the relay port's pattern - and the
# relay's words stay in the run's log, where a person reads them.
#
# A TEST'S HOME TELLS NOBODY (cli/ServicesTell.ps1, the same guard): a Horde home under the temp folder
# is a suite's, and a tell from one is refused before any messenger or seat is looked for - the seat is
# found in a store whose place does not follow the Horde home.
#
# THE CALLER LOADS THE PORT: messengers/Port.ps1 and every messenger's file must have been dot-sourced
# in the scope this is called from, so the blocks a messenger registered still see its helpers. The
# relay run's channels do it (channels/decisions and channels/chat load them at script level).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\TextUuid.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Device.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\SessionSeat.ps1")

$script:HordeRelayRunTellNeeds = @("body.untyped", "idempotent.post")
$script:HordeRelayRunTellRole = "warchief"
# Who the notice is from: the run is no session, so it names itself in a session id's shape, and wears
# the label of the setting fromLabel (a messenger may hold a message whose sender it cannot place).
$script:HordeRelayRunTellFrom = "horde-relay-run"
# How long the notice may wait in a mailbox: the link's most, 7 days (messengers/Port.ps1).
$script:HordeRelayRunTellTtlSeconds = 604800
$script:HordeRelayRunTellStages = @("accepted", "handed-over", "seen")
# A mailbox as relays/Port.ps1 names one: nothing else is ever repeated in a notice.
$script:HordeRelayRunTellMailboxPattern = '\A[a-z0-9][a-z0-9-]{0,62}/[a-z0-9][a-z0-9-]{0,62}\z'

function Format-HordeRelayFullNotice {
    # PURE. The words of the notice (header, WHAT IT SAYS): fixed sentences and the mailbox's name. A
    # name that is not a mailbox's is not repeated either.
    param([string]$Mailbox)
    $where = "a mailbox of this horde"
    if ($Mailbox -cmatch $script:HordeRelayRunTellMailboxPattern) { $where = "the mailbox " + $Mailbox }
    return (@(
        "HORDE RELAY - needs attention",
        ("The relay is refusing what this machine sends to " + $where + ": it is full (the mailbox, or the account's storage)."),
        "Until that is put right, nothing new reaches the founder's phone from this machine: no question, no reply, no chat, no progress.",
        "The relay run keeps trying, and says in its own log what the relay answered and when it is over."
    ) -join "`n")
}

function Get-HordeRelayFullNoticeId {
    # The notice's id (header, ONCE): this home, the mailbox and the UTC day, as a lowercase uuid.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Mailbox, [Parameter(Mandatory = $true)][datetime]$Day)
    return (ConvertTo-HordeTextUuid -Text ("horde-relay-full`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant() + "`n" + $Mailbox + "`n" + $Day.ToUniversalTime().ToString("yyyy-MM-dd")))
}

function Test-HordeRelayRunHomeIsATests {
    # Is -HordeHome under the temp folder (header, A TEST'S HOME TELLS NOBODY)? Compared resolved and
    # without case. A home that cannot be resolved is treated as a test's: telling nobody is the safe
    # mistake.
    param([string]$HordeHome, [string]$TempRoot = "")
    if ($TempRoot -eq "") { $TempRoot = [System.IO.Path]::GetTempPath() }
    try {
        $under = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd('\', '/') + '\'
        $full = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\', '/') + '\'
        return [bool]$full.StartsWith($under, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $true }
}

function Send-HordeRelayFullNotice {
    # Post the notice for -Mailbox to the warchief's session: { told; problem } - told $true when a
    # messenger took it, else problem says why not in one sentence. Never throws for the far end.
    # -Seat, -TempRoot and -Day are for a suite that hands in its own.
    param([Parameter(Mandatory = $true)][string]$Mailbox, [Parameter(Mandatory = $true)][string]$HordeHome, [string]$FromLabel = "", [scriptblock]$Seat = $null, [string]$TempRoot = "", $Day = $null)
    $done = { param([bool]$Told, [string]$Problem) return [pscustomobject]@{ told = $Told; problem = $Problem } }
    # BEFORE ANYTHING IS LOOKED FOR: a test's home tells nobody (header).
    if (Test-HordeRelayRunHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return (& $done $false "this Horde home is under the temp folder, so it is a test's: nobody is told") }
    $found = Find-HordeMessenger -Require $script:HordeRelayRunTellNeeds
    if ($found.state -ceq "absent") { return (& $done $false ("no messenger on this machine can deliver to a session (" + $found.reason + ")")) }
    if ($found.state -cne "known") { return (& $done $false ("no messenger was chosen: " + $found.reason)) }
    $messenger = $found.value
    if ($null -eq $Seat) { $Seat = { return (Get-HordeRoleSeat -Role $script:HordeRelayRunTellRole) } }
    $where = $null
    try { $where = @(& $Seat) | Select-Object -Last 1 } catch { $where = New-HordeUnknown -Reason "the seat could not be read" -ErrorRecord $_ }
    if ($null -eq $where -or "$($where.state)" -ceq "absent") { return (& $done $false ("no session holds the role of " + $script:HordeRelayRunTellRole + ", so there is nobody to tell")) }
    if ("$($where.state)" -cne "known") { return (& $done $false ("the " + $script:HordeRelayRunTellRole + "'s session cannot be told: " + $where.reason)) }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return (& $done $false ("this machine's device id could not be had: " + $_.Exception.Message)) }
    if ($null -eq $Day) { $Day = [datetime]::UtcNow }
    $message = [pscustomobject]@{
        messageId = (Get-HordeRelayFullNoticeId -HordeHome $HordeHome -Mailbox $Mailbox -Day $Day); sessionId = "" + $where.value.sessionId
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeRelayRunTellFrom; label = $FromLabel }
        body = (Format-HordeRelayFullNotice -Mailbox $Mailbox); ttlSeconds = $script:HordeRelayRunTellTtlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
    if ($posted.state -ceq "known" -and $script:HordeRelayRunTellStages -ccontains "$($posted.value.stage)") { return (& $done $true "") }
    if ($posted.state -ceq "known") { return (& $done $false ("messenger " + $messenger.name + " answered " + $posted.value.stage)) }
    return (& $done $false ("messenger " + $messenger.name + " did not take it: " + $posted.reason))
}
