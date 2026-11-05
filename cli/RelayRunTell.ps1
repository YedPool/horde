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
# THE NOTICE COUNTS AS TOLD ONLY WHEN THE WARCHIEF'S OWN SESSION TOOK IT (T-0391 slice 5; the chat's own rule, channels/chat/Taken.ps1,
# and the routed answers', the doorbell's and the photo notice's: decisions/NoticeTaken.ps1, used as it is). The messenger ACCEPTING the
# post was counted as the warchief being told, and the run said "the warchief was told" for a notice no session had taken. Now:
#   - MARK FIRST, THEN POST. Send-HordeRelayFullNotice puts the notice on the awaiting list BEFORE it posts. A list that cannot be read or
#     written means no post, the reason said, and the notice tried again on a later turn.
#   - A post the messenger REFUSES (a known answer with another stage) takes its mark off; an UNKNOWN result keeps it, for a post that may
#     have landed must stay watched.
#   - DELIVERED is the session's own TAKEN (handed-over or seen), said by Invoke-HordeRelayRunTellTakenTick; accepted is not.
#   - ONE ALARM at takenAlarmSeconds without a TAKEN, asked about every takenAfterAlarmSeconds after it, given up with a second ALARM
#     when the notice is 7 days old. A restart does nothing twice: the list is a file, the alarm is in the mark, and the notice id is the
#     same for the same mailbox on the same UTC day (wezfleet keeps one message per id, lib/MailPost.ps1 already-posted).
#   - THE LINES REACH THE RUN'S LOG: the tick returns them, and cli/RelayRun.ps1 (Invoke-HordeRelayRunPutNotes) says each one.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\TextUuid.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Device.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\SessionSeat.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "decisions\NoticeTaken.ps1")

$script:HordeRelayRunTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
$script:HordeRelayRunTellRole = "warchief"
# Who the notice is from: the run is no session, so it names itself in a session id's shape, and wears
# the label of the setting fromLabel (a messenger may hold a message whose sender it cannot place).
$script:HordeRelayRunTellFrom = "horde-relay-run"
# How long the notice may wait in a mailbox: the link's most, 7 days (messengers/Port.ps1).
$script:HordeRelayRunTellTtlSeconds = 604800
# What a post's stage must be for the messenger to have taken it; any other stage of a known answer is a refusal.
$script:HordeRelayRunTellStages = @("accepted", "handed-over", "seen")
# The awaiting list of these notices: one file under the home, the words its lines use (decisions/NoticeTaken.ps1).
$script:HordeRelayRunTellTakenKind = New-HordeDecisionNoticeKind -Path @("relay", "run-full-taken.json") -TempPrefix "run-full-taken" -Ledger "the relay-full notices' awaiting ledger" -List "the awaiting list of relay-full notices" -Label "relay run" -Notice "relay-full notice" -Owner "the warchief's" -Detail { param($Entry) return "the relay refusing a mailbox of this horde" }
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
    # The notice's id (header, ONCE): this home, the mailbox and the start of THIS FILL (the UTC ms the run first saw the mailbox
    # full, kept across restarts by Get-HordeRelayRunFillStart), as a lowercase uuid. Each fill has its own id: a mailbox that emptied
    # and filled again would otherwise post the SAME id, which wezfleet answers already-posted with the first copy's stage, waking
    # nobody (review of PR 419, round 1).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Mailbox, [Parameter(Mandatory = $true)][long]$Fill)
    return (ConvertTo-HordeTextUuid -Text ("horde-relay-full`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant() + "`n" + $Mailbox + "`n" + $Fill))
}

function Get-HordeRelayRunFillPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "run-full-fill.txt")
}

function Read-HordeRelayRunFills {
    # The fills this home's run is in: { ok; fills } - fills maps a mailbox to the UTC ms its fill began. One line each, "<mailbox> <ms>"
    # (plain text: a mailbox is held to the relay port's pattern, so nothing needs parsing). A missing file is no fills; a line that is
    # not one is skipped; a file that cannot be read is ok $false.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $fills = @{}
    $path = Get-HordeRelayRunFillPath -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return [pscustomobject]@{ ok = $true; fills = $fills } }
    try {
        foreach ($line in @([System.IO.File]::ReadAllLines($path))) {
            if ($line -cmatch ('\A([a-z0-9][a-z0-9-]{0,62}/[a-z0-9][a-z0-9-]{0,62}) ([0-9]{1,15})\z')) { $fills[$Matches[1]] = [long]$Matches[2] }
        }
    } catch { return [pscustomobject]@{ ok = $false; fills = $fills } }
    return [pscustomobject]@{ ok = $true; fills = $fills }
}

function Write-HordeRelayRunFills {
    # The fills, replaced whole in one rename (core/FileAtomic.ps1). $true when written; never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][hashtable]$Fills)
    $path = Get-HordeRelayRunFillPath -HordeHome $HordeHome
    $tmp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        $text = ((@($Fills.Keys | Sort-Object) | ForEach-Object { $_ + " " + $Fills[$_] }) -join "`n") + "`n"
        [System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::ASCII.GetBytes($text))
        Move-HordeFileAtomic -From $tmp -To $path
        return $true
    } catch { try { [System.IO.File]::Delete($tmp) } catch { }; return $false }
}

function Get-HordeRelayRunFillStart {
    # The UTC ms the fill of -Mailbox began: the one kept in the home's file when there is one (a restart within one fill reuses it, so
    # the same notice id is posted and wezfleet keeps one message), else -Now, written down. A file that cannot be written still gives
    # -Now: this run then keeps it in memory, and only a restart inside the fill posts a second notice.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Mailbox, [Parameter(Mandatory = $true)][long]$NowMs)
    $r = Read-HordeRelayRunFills -HordeHome $HordeHome
    if ($r.ok -and $r.fills.ContainsKey($Mailbox)) { return [long]$r.fills[$Mailbox] }
    if ($r.ok) { $r.fills[$Mailbox] = $NowMs; [void](Write-HordeRelayRunFills -HordeHome $HordeHome -Fills $r.fills) }
    return $NowMs
}

function Clear-HordeRelayRunFill {
    # The mailbox is no longer full: its fill is over, and the next one gets its own start. Never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Mailbox)
    $r = Read-HordeRelayRunFills -HordeHome $HordeHome
    if (-not $r.ok -or -not $r.fills.ContainsKey($Mailbox)) { return }
    $r.fills.Remove($Mailbox)
    [void](Write-HordeRelayRunFills -HordeHome $HordeHome -Fills $r.fills)
}

function Test-HordeRelayRunNoticeListed {
    # Is the notice on the awaiting list now? $false too when the list cannot be read (Add then fails and nothing is posted).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId)
    $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome
    if ($r.state -cne "known") { return $false }
    $id = $NoticeId.Replace("-", "")
    foreach ($mark in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $mark; if ($null -ne $e -and $e.messageId -ceq $id) { return $true } }
    return $false
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
    # Post the notice for -Mailbox to the warchief's session, marked first: { told; problem; lines } - told $true when a messenger
    # took the post (it is then on the awaiting list, and only the session's own TAKEN makes it delivered), else problem says why
    # not in one sentence. lines are for the run's log. Never throws for the far end.
    # -Fill is the start of the mailbox's fill (Get-HordeRelayRunFillStart): the notice id is made of it. -Seat, -TempRoot and -Day are for a suite
    # that hands in its own.
    param([Parameter(Mandatory = $true)][string]$Mailbox, [Parameter(Mandatory = $true)][string]$HordeHome, [string]$FromLabel = "", [scriptblock]$Seat = $null, [string]$TempRoot = "", $Day = $null, [long]$Fill = 0)
    $lines = New-Object System.Collections.ArrayList
    $done = { param([bool]$Told, [string]$Problem, [bool]$Reposted = $false) return [pscustomobject]@{ told = $Told; problem = $Problem; lines = @($lines.ToArray()); reposted = $Reposted } }
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
        messageId = (Get-HordeRelayFullNoticeId -HordeHome $HordeHome -Mailbox $Mailbox -Fill $Fill); sessionId = "" + $where.value.sessionId
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeRelayRunTellFrom; label = $FromLabel }
        body = (Format-HordeRelayFullNotice -Mailbox $Mailbox); ttlSeconds = $script:HordeRelayRunTellTtlSeconds
    }
    # THE MARK IS WRITTEN BEFORE THE POST. A list that cannot be read or written means nothing is posted. A crash between the mark and
    # the post only costs an alarm at takenAlarmSeconds: the next pass posts the same notice id, which the messenger keeps as one.
    $at = $(if ($Day -is [datetime]) { $Day.ToUniversalTime() } else { [datetime]::UtcNow })
    $wasListed = Test-HordeRelayRunNoticeListed -HordeHome $HordeHome -NoticeId $message.messageId
    $awaited = Add-HordeDecisionNoticeTaken -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId -Answer 0 -SessionId ("" + $where.value.sessionId) -Now $at
    foreach ($l in @($awaited.lines)) { [void]$lines.Add($l) }
    if (-not $awaited.ok) { return (& $done $false ("the notice cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be")) }
    $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
    if ($posted.state -ceq "known" -and $script:HordeRelayRunTellStages -ccontains "$($posted.value.stage)") {
        # ALREADY POSTED, AND THIS PASS WROTE A BRAND-NEW MARK: the messenger answered with the first copy's stage and woke nobody, so
        # that stage says nothing of THIS post. It is never counted as fresh: the mark is taken off (or the next look would log a TAKEN for
        # a notice never sent again), and the log says so plainly. The notice is not posted again (told), whatever the first copy became.
        if ("$($posted.value.reason)" -clike "already-posted*" -and -not $wasListed) {
            $null = Remove-HordeDecisionNoticeTaken -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId
            [void]$lines.Add("relay run: the notice " + $message.messageId + " for " + $Mailbox + " was NOT sent again: the messenger already held a copy of it from an earlier post and woke nobody, so it is not counted as delivered")
            return (& $done $true "" $true)
        }
        return (& $done $true "")
    }
    # A REFUSED POST LEAVES NO MARK (the notice is in no mailbox, so a mark would alarm "not taken" for something never sent). ONLY A
    # KNOWN REFUSAL removes it: an UNKNOWN result may have landed, and a notice that landed must stay watched.
    if ($posted.state -ceq "known") {
        $why = "messenger " + $messenger.name + " answered " + $posted.value.stage
        $removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId
        if (-not $removed.ok) { $why = $why + "; its awaiting mark could not be removed (" + $removed.reason + ")" }
        return (& $done $false $why)
    }
    return (& $done $false ("messenger " + $messenger.name + " did not take it: " + $posted.reason))
}

function Invoke-HordeRelayRunTellTakenTick {
    # Ask about the relay-full notices awaiting the warchief's own TAKEN and say what became of them (NoticeTaken.ps1): the lines, for
    # the run's log. -Memory is the run's table between passes. The messenger is found as the notice was posted; when none can be had
    # now the clock alone speaks. Never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][hashtable]$Memory, [Parameter(Mandatory = $true)][datetime]$Now, [double]$AlarmSeconds = 90, [double]$AfterAlarmSeconds = 60)
    $messenger = $null
    try { $found = Find-HordeMessenger -Require $script:HordeRelayRunTellNeeds; if ($found.state -ceq "known") { $messenger = $found.value } } catch { $messenger = $null }
    try {
        $tick = Invoke-HordeDecisionNoticeTakenTick -Kind $script:HordeRelayRunTellTakenKind -HordeHome $HordeHome -Messenger $messenger -Now $Now.ToUniversalTime() -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds $script:HordeRelayRunTellTtlSeconds -Memory $Memory
        return @($tick.lines)
    } catch { return @("relay run: the awaiting list of relay-full notices could not be asked: " + $_.Exception.Message) }
}
