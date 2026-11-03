# decisions/RouteTaken.ps1 - a routed answer is DELIVERED only when the Orc's own session took it (task T-0391, slice 1 of 6).
#
# THE BUG. decisions/Route.ps1 gave the founder's answer to the asking Orc through the messenger and counted it
# routed the moment the messenger ACCEPTED the post. Accepted is not delivered: the notice is in the Orc's mailbox,
# and the session may never be prompted (the wake knock can be refused while the Orc is mid-turn). That is the bug
# the founder named for phone chat lines (T-0281, fixed by PR 340, channels/chat/Taken.ps1): "accepted" was taken
# for the end of the road and the one fact that says whether the session has it - the receiving session's own hook
# confirming the notice in its transcript, which the messenger port reports as the stage handed-over and then seen
# (TAKEN) - was never asked for.
#
# THE RULE, the chat's own (Taken.ps1 is used as it is; nothing of its decision is written again here):
#   - MARK FIRST, THEN POST (slice 2). The notice is put on the awaiting list BEFORE it is posted, and the route record is
#     written after the messenger accepted it. A list that cannot be read or written posts nothing (the answer waits, the
#     reason is said); a post the messenger REFUSES (a known refusal, not an unknown result) takes its mark off again, so a
#     notice that was never sent never alarms; KNOWN COST: a crash between the mark and the post, then the question closing,
#     gives one false NOT TAKEN alarm;
#     a crash between mark and post costs one alarm at takenAlarmSeconds, and the next pass posts the same id (wezfleet
#     writes it once and knocks nobody again: its lib/MailPost.ps1 already-posted). The route record means "sent" (it is
#     what keeps the answer from being sent twice); it never means delivered. The pass says "SENT ... awaiting TAKEN".
#   - DELIVERED is the session's own TAKEN: the messenger's status for the notice, asked by the id the notice was
#     posted under, says handed-over or seen. Only then is the line "TAKEN ... delivered" said and the mark removed.
#   - ALARMED, ONCE. Not taken in takenAlarmSeconds (90, the chat's number and for its reasons: the knock and the wake
#     watcher's three re-tries have had their chance): ONE line in capitals, "ALARM: ...", in the runner's log; the mark
#     is kept with alarmed set, and the notice stays in the Orc's mailbox. A status that cannot be had (unknown,
#     absent) is not a confirmation: the alarm is raised on the clock alone.
#   - NEVER DROPPED. After the alarm the notice is asked about every takenAfterAlarmSeconds until it is taken (a late
#     TAKEN says so: "TAKEN after the alarm") or the notice is a notice-ttl old (7 days, the mailbox's own), when it
#     is given up with a second line in capitals. A notice the messenger holds for good is told the same way. Past
#     HordeChatTakenKept marks the oldest is given up with a line in capitals, never in silence.
#   - A RESTART DOES NOTHING TWICE. The list is a file (<HORDE_HOME>\relay\decisions\route-taken.json), written whole
#     in one rename BEFORE the post, so a router that restarts reads it back: the mark is added once (a
#     resend of the same notice keeps its own clock), the alarm is in the mark, and the notice id is the same, so a
#     messenger that keeps one message per id is not sent a second one.
#
# WHAT THIS DOES NOT DO: knock again (the wake watcher's, core/Wake.ps1), put a word of "Delivered" on the phone
# (the phone shows no state for a routed answer today; the awaiting list is the machine half it can be drawn from:
# Get-HordeDecisionRouteTakenState), or re-post a final-held notice under another id.
#
# THE PASS MODEL. A pass is not a wait: it asks every awaiting mark once and goes on. The Turn's pass runs when the
# store changed or passSeconds (60) have passed, so a TAKEN is seen within a pass of its hook and an alarm within a
# pass of takenAlarmSeconds. At most HordeChatTakenAsksPerTick marks are asked in one pass (a status is a process),
# the longest-unasked first, so a long list cannot starve one.
#
# SHARED (T-0391 slice 3): the list's engine - add, remove, ask - is decisions/NoticeTaken.ps1, which the doorbell (Notify.ps1) uses too;\n# this file holds the ROUTED ANSWERS' kind of it (their file and their words) under the names Route.ps1 and its suites call.\n#\n# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

$script:HordeDecisionRouteTakenRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "NoticeTaken.ps1")

# The routed answers' kind of the awaiting list: its file, and the words its lines are said in.
$script:HordeDecisionRouteTakenKind = New-HordeDecisionNoticeKind -Path @("relay", "decisions", "route-taken.json") -TempPrefix "route-taken" -Ledger "the routed-answers ledger" -List "the awaiting list of routed answers" -Label "route" -Notice "routed notice" -Owner "the Orc's" -Detail { param($Entry) return ("answer record " + $Entry.seq) }

function Get-HordeDecisionRouteTakenPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Get-HordeDecisionNoticeTakenPath -Kind $script:HordeDecisionRouteTakenKind -HordeHome $HordeHome)
}

function Read-HordeDecisionRouteTaken {
    # The awaiting list of routed notices: known { awaiting }, the empty list for no file, unknown for a file that does
    # not hold together (never a guess, never started over).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Read-HordeDecisionNoticeTaken -Kind $script:HordeDecisionRouteTakenKind -HordeHome $HordeHome)
}

function Get-HordeDecisionRouteTakenState {
    # What became of the notices that are not yet taken, for a caller that draws it (the phone, a list): one object per
    # mark, { noticeId; answer; session; postedMs; alarmed }. Empty for no file; $null when the file cannot be read.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $r = Read-HordeDecisionRouteTaken -HordeHome $HordeHome
    if ($r.state -cne "known") { return $null }
    $out = New-Object System.Collections.ArrayList
    foreach ($m in @($r.value.awaiting)) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $m
        if ($null -ne $e) { [void]$out.Add([pscustomobject]@{ noticeId = $e.messengerId; answer = $e.seq; session = $e.session; postedMs = $e.postedMs; alarmed = $e.alarmed }) }
    }
    return @($out.ToArray())
}

function Get-HordeDecisionRouteTakenNowMs {
    param([datetime]$Now)
    return (Get-HordeDecisionNoticeTakenNowMs -Now $Now)
}

function Add-HordeDecisionRouteTaken {
    # A notice about to be posted, onto the awaiting list and the file, once: { ok; reason; lines } (NoticeTaken.ps1).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId, [Parameter(Mandatory = $true)][long]$Answer, [string]$SessionId = "", [Parameter(Mandatory = $true)][datetime]$Now)
    return (Add-HordeDecisionNoticeTaken -Kind $script:HordeDecisionRouteTakenKind -HordeHome $HordeHome -NoticeId $NoticeId -Answer $Answer -SessionId $SessionId -Now $Now)
}

function Remove-HordeDecisionRouteTaken {
    # A notice's mark off the list and the file (a post the messenger refused): { ok; reason }. Never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId)
    return (Remove-HordeDecisionNoticeTaken -Kind $script:HordeDecisionRouteTakenKind -HordeHome $HordeHome -NoticeId $NoticeId)
}

function Invoke-HordeDecisionRouteTakenTick {
    # Ask about every awaiting routed notice that is due and act: { lines; delivered; alarmed; waiting; failed } (NoticeTaken.ps1).
    param([Parameter(Mandatory = $true)][string]$HordeHome, $Messenger, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][double]$AlarmSeconds, [Parameter(Mandatory = $true)][double]$AfterAlarmSeconds, [double]$TtlSeconds = 604800, [hashtable]$Memory = $null)
    return (Invoke-HordeDecisionNoticeTakenTick -Kind $script:HordeDecisionRouteTakenKind -HordeHome $HordeHome -Messenger $Messenger -Now $Now -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds $TtlSeconds -Memory $Memory)
}