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
#     reason is said); a post the messenger REFUSES takes its mark off again, so a notice that was never sent never alarms;
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
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

$script:HordeDecisionRouteTakenRoot = Split-Path -Parent $PSScriptRoot
foreach ($routeTakenCore in @("Tristate", "JsonText", "FileAtomic")) {
    . (Join-Path $script:HordeDecisionRouteTakenRoot ("core\" + $routeTakenCore + ".ps1"))
}
. (Join-Path $script:HordeDecisionRouteTakenRoot "channels\chat\Taken.ps1")

# The mark's "sender key id" is a field of the chat's mark that a routed notice has no use for (it was posted by the
# router, not signed by a phone key): a fixed 32 hex digits, so the one mark format serves.
$script:HordeDecisionRouteTakenFrom = "00000000000000000000000000000000"

function Get-HordeDecisionRouteTakenPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "decisions", "route-taken.json")
}

function Read-HordeDecisionRouteTaken {
    # The awaiting list of routed notices: known { awaiting }, the empty list for no file, unknown for a file that does
    # not hold together (never a guess, never started over).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Read-HordeTakenLedgerFile -Path (Get-HordeDecisionRouteTakenPath -HordeHome $HordeHome) -What "the routed-answers ledger" -Noun "notice")
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
    return [long]($Now.ToUniversalTime() - [datetime]"1970-01-01T00:00:00Z").TotalMilliseconds
}

function Add-HordeDecisionRouteTaken {
    # A notice the messenger accepted, onto the awaiting list and the file, once: { ok; reason; lines }. A notice already
    # there (the same id sent again after a crash) keeps its own clock and its alarm. The oldest mark past the list's
    # size is given up WITH a line in capitals. ok is $false when the file cannot be read or written: the caller must then
    # not write the route record (the next pass sends the same notice and adds it again).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId, [Parameter(Mandatory = $true)][long]$Answer, [string]$SessionId = "", [Parameter(Mandatory = $true)][datetime]$Now)
    $lines = @()
    $r = Read-HordeDecisionRouteTaken -HordeHome $HordeHome
    if ($r.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = ("the routed-answers ledger cannot be read: " + $r.reason); lines = $lines } }
    $ledger = [pscustomobject]@{ awaiting = @($r.value.awaiting) }
    $session = $(if ($SessionId -cmatch '\A[A-Za-z0-9._:-]{1,128}\z') { $SessionId } else { "" })
    $entry = [pscustomobject]@{ messageId = $NoticeId.Replace("-", ""); messengerId = $NoticeId; postedMs = (Get-HordeDecisionRouteTakenNowMs -Now $Now); from = $script:HordeDecisionRouteTakenFrom; seq = $Answer; alarmed = $false; woken = $false; session = $session }
    if ($null -ne (Get-HordeChatTakenEntry -State $ledger -MessageId $entry.messageId)) { return [pscustomobject]@{ ok = $true; reason = ""; lines = $lines } }
    $overflow = @(Get-HordeChatTakenOverflow -State $ledger)
    [void](Add-HordeChatTaken -State $ledger -Entry $entry)
    try { Write-HordeTakenLedgerFile -Path (Get-HordeDecisionRouteTakenPath -HordeHome $HordeHome) -Ledger $ledger -TempPrefix "route-taken" }
    catch { return [pscustomobject]@{ ok = $false; reason = ("the routed-answers ledger could not be written: " + $_.Exception.Message); lines = $lines } }
    $lines = @(foreach ($old in $overflow) { "ALARM: routed notice " + $old.messengerId + " (answer record " + $old.seq + ") left the awaiting list because it is full; it is no longer watched, but it may still be in the Orc's mailbox and be taken" })
    return [pscustomobject]@{ ok = $true; reason = ""; lines = $lines }
}

function Remove-HordeDecisionRouteTaken {
    # A notice's mark off the list and the file (a post the messenger refused, so the notice is in no mailbox): { ok; reason }.
    # A notice not listed is already as wanted. Never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId)
    $r = Read-HordeDecisionRouteTaken -HordeHome $HordeHome
    if ($r.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = "the routed-answers ledger cannot be read: " + $r.reason } }
    $id = $NoticeId.Replace("-", "")
    $keep = @(@($r.value.awaiting) | Where-Object { $e = ConvertFrom-HordeChatTakenMark -Mark $_; $null -eq $e -or $e.messageId -cne $id })
    if ($keep.Count -eq @($r.value.awaiting).Count) { return [pscustomobject]@{ ok = $true; reason = "" } }
    try { Write-HordeTakenLedgerFile -Path (Get-HordeDecisionRouteTakenPath -HordeHome $HordeHome) -Ledger ([pscustomobject]@{ awaiting = $keep }) -TempPrefix "route-taken" }
    catch { return [pscustomobject]@{ ok = $false; reason = "the routed-answers ledger could not be written: " + $_.Exception.Message } }
    return [pscustomobject]@{ ok = $true; reason = "" }
}

function Invoke-HordeDecisionRouteTakenTick {
    # Ask about every awaiting notice that is due and act (Get-HordeChatTakenAction, as the chat does): { lines;
    # delivered; alarmed; waiting; failed }. -Messenger is the one the notices were posted through ($null when none can
    # be had now: the clock alone then speaks). -Memory is the caller's table, kept between passes (when each mark was
    # last asked). Never throws; a list that cannot be read is said and left as it is.
    param([Parameter(Mandatory = $true)][string]$HordeHome, $Messenger, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][double]$AlarmSeconds, [Parameter(Mandatory = $true)][double]$AfterAlarmSeconds, [double]$TtlSeconds = 604800, [hashtable]$Memory = $null)
    $lines = New-Object System.Collections.ArrayList
    $none = { param($Failed) return [pscustomobject]@{ lines = @($lines.ToArray()); delivered = 0; alarmed = 0; waiting = 0; failed = [bool]$Failed } }
    if ($null -eq $Memory) { $Memory = @{} }
    $r = Read-HordeDecisionRouteTaken -HordeHome $HordeHome
    if ($r.state -cne "known") { [void]$lines.Add("route: the awaiting list of routed answers cannot be read: " + $r.reason); return (& $none $true) }
    $awaiting = @($r.value.awaiting)
    if ($awaiting.Count -eq 0) { return (& $none $false) }
    $nowMs = Get-HordeDecisionRouteTakenNowMs -Now $Now
    # Every pass asks every mark that is due: the Turn spaces the passes (passSeconds), so the alarmed marks are
    # slowed to AfterAlarmSeconds here and the rest are asked on each pass. Bounded and longest-unasked first.
    $due = New-Object System.Collections.ArrayList
    $pos = 0
    foreach ($mark in $awaiting) {
        $pos++
        $de = ConvertFrom-HordeChatTakenMark -Mark $mark
        if ($null -eq $de) { continue }
        $last = $(if ($Memory.ContainsKey($de.messageId)) { [long]$Memory[$de.messageId] } else { [long]0 })
        $every = $(if ($de.alarmed) { [long]($AfterAlarmSeconds * 1000) } else { [long]0 })
        if ($nowMs - $last -ge $every) { [void]$due.Add([pscustomobject]@{ id = $de.messageId; last = $last; pos = $pos }) }
    }
    $mayAsk = @{}
    foreach ($x in @($due.ToArray() | Sort-Object -Property last, pos | Select-Object -First $script:HordeChatTakenAsksPerTick)) { $mayAsk[$x.id] = $true }
    $keep = New-Object System.Collections.ArrayList
    $changed = $false
    $delivered = 0
    $alarmed = 0
    foreach ($mark in $awaiting) {
        $e = ConvertFrom-HordeChatTakenMark -Mark $mark
        if ($null -eq $e) { [void]$lines.Add("route: an awaiting mark that is not one was dropped"); $changed = $true; continue }
        if (-not $mayAsk.ContainsKey($e.messageId)) { [void]$keep.Add($mark); continue }
        $Memory[$e.messageId] = $nowMs
        $status = $null
        if ($null -ne $Messenger) { $status = Get-HordeMessengerStatus -Messenger $Messenger -MessageId $e.messengerId }
        $age = ($nowMs - $e.postedMs) / 1000.0
        # A FAILED WRITE AFTER AN ALARM (review nit): the alarm was said but not saved; this process remembers it so the next
        # pass does not say it again, and saves it then. A restart before that repeats the line once, which is accepted.
        $wasAlarmed = $e.alarmed
        $e.alarmed = ($e.alarmed -or $Memory.ContainsKey("alarmed-" + $e.messageId))
        $act = Get-HordeChatTakenAction -Status $status -AgeSeconds $age -Alarmed $e.alarmed -AlarmSeconds $AlarmSeconds -TtlSeconds $TtlSeconds
        $name = "routed notice " + $e.messengerId + " (answer record " + $e.seq + ")"
        switch ($act) {
            "wait" {
                if ($e.alarmed -and -not $wasAlarmed) { $changed = $true; $saved = ConvertTo-HordeChatTakenMark -Entry $e; [void]$keep.Add($saved) } else { [void]$keep.Add($mark) }
            }
            "confirmed" {
                $changed = $true; $delivered++
                $Memory["delivered-" + $e.messengerId] = $true
                [void]$lines.Add("TAKEN: " + $name + " was taken by the Orc's own session after " + [int]$age + " s" + $(if ($e.alarmed) { ", after the alarm" } else { "" }) + ": delivered")
            }
            "held" { $changed = $true; [void]$lines.Add("ALARM: " + $name + " NOT DELIVERED: the messenger holds it for good; it is no longer watched") }
            "expired" { $changed = $true; [void]$lines.Add("ALARM: " + $name + " NOT DELIVERED, given up after " + [int]$age + " s; it is no longer watched, but it may still be in the Orc's mailbox") }
            "alarm" {
                $changed = $true; $alarmed++
                $e.alarmed = $true
                $Memory["alarmed-" + $e.messageId] = $true
                [void]$keep.Add((ConvertTo-HordeChatTakenMark -Entry $e))
                [void]$lines.Add("ALARM: " + $name + " was NOT TAKEN by the Orc's session in " + [int]$age + " s (the wake is the wake watcher's, core/Wake.ps1); it stays in the Orc's mailbox and is asked about until it is taken")
            }
        }
    }
    if ($changed) {
        try { Write-HordeTakenLedgerFile -Path (Get-HordeDecisionRouteTakenPath -HordeHome $HordeHome) -Ledger ([pscustomobject]@{ awaiting = @($keep.ToArray()) }) -TempPrefix "route-taken" }
        catch { [void]$lines.Add("route: the awaiting list of routed answers could not be written: " + $_.Exception.Message + "; it is read again on the next pass"); return (& $none $true) }
    }
    $result = & $none $false
    $result.delivered = $delivered
    $result.alarmed = $alarmed
    $result.waiting = $keep.Count
    return $result
}
