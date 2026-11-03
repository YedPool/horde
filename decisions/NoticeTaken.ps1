# decisions/NoticeTaken.ps1 - the ONE awaiting-list engine for a notice a decisions sender posted: it is DELIVERED only when the
# target session's own side took it (task T-0391; slice 1 routed answers, slice 3 the doorbell).
#
# WHY ONE FILE. The routed answers (decisions/RouteTaken.ps1, PRs 415 and 416, three fresh reviews each) and the doorbell
# (decisions/Notify.ps1) have the same bug and need the same cure: the messenger ACCEPTING a post was counted as the notice
# being delivered, and the one fact that says whether the session has it - its own hook confirming the notice, which the
# messenger port reports as the stage handed-over and then seen (TAKEN) - was never asked for. What the reviews taught is in
# this file once, so a fix to it is a fix to both senders. Each sender passes its KIND (New-HordeDecisionNoticeKind): the
# file its marks live in and the words its lines use. Nothing else differs.
#
# THE RULE (the chat's own, channels/chat/Taken.ps1, used as it is; nothing of its decision is written again here):
#   - MARK FIRST, THEN POST. The caller puts the notice on the awaiting list (Add-HordeDecisionNoticeTaken) BEFORE it posts. A
#     list that cannot be read or written means no post, the reason said, the item pending. A post the messenger REFUSES (a
#     known refusal, not an unknown result) takes its mark off again (Remove-HordeDecisionNoticeTaken); an UNKNOWN result keeps
#     it, for a post that may have landed must stay watched.
#   - DELIVERED is the session's own TAKEN: the messenger's status for the notice, asked by the id it was posted under, says
#     handed-over or seen. Only then is the line "TAKEN ... delivered" said and the mark removed.
#   - ALARMED, ONCE. Not taken in AlarmSeconds: ONE line in capitals, "ALARM: ...", the mark is kept with alarmed set, and the
#     notice stays in the mailbox. A status that cannot be had (unknown, absent) is not a confirmation: the clock alone alarms.
#   - NEVER DROPPED. After the alarm the notice is asked about every AfterAlarmSeconds until it is taken (a late TAKEN says so)
#     or it is a notice-ttl old (7 days), when it is given up with a second line in capitals. A notice the messenger holds for
#     good is told the same way. Past HordeChatTakenKept marks the oldest is given up with a line in capitals.
#   - A RESTART DOES NOTHING TWICE. The list is a file, written whole in one rename BEFORE the post, so a restarted sender reads
#     it back: the mark is added once (a resend keeps its own clock), the alarm is in the mark, and the notice id is the same,
#     so a messenger that keeps one message per id (wezfleet, lib/MailPost.ps1 already-posted) is not sent a second one.
#
# THE PASS MODEL. A pass is not a wait: Invoke-HordeDecisionNoticeTakenTick asks every awaiting mark that is due once and goes
# on. At most HordeChatTakenAsksPerTick marks are asked in one pass (a status is a process), the longest-unasked first.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

$script:HordeDecisionNoticeTakenRoot = Split-Path -Parent $PSScriptRoot
foreach ($noticeTakenCore in @("Tristate", "JsonText", "FileAtomic")) {
    . (Join-Path $script:HordeDecisionNoticeTakenRoot ("core\" + $noticeTakenCore + ".ps1"))
}
. (Join-Path $script:HordeDecisionNoticeTakenRoot "channels\chat\Taken.ps1")

# The mark's "sender key id" is a field of the chat's mark that a posted notice has no use for (it was posted by horde, not
# signed by a phone key): a fixed 32 hex digits, so the one mark format serves.
$script:HordeDecisionNoticeTakenFrom = "00000000000000000000000000000000"

function New-HordeDecisionNoticeKind {
    # What one sender's list is called and where it lives: { path (parts under the home); tempPrefix; ledger; list; label;
    # notice; owner; detail }. detail is a script block from an entry to the words after the notice's id in its name.
    param([Parameter(Mandatory = $true)][string[]]$Path, [Parameter(Mandatory = $true)][string]$TempPrefix, [Parameter(Mandatory = $true)][string]$Ledger, [Parameter(Mandatory = $true)][string]$List, [Parameter(Mandatory = $true)][string]$Label, [Parameter(Mandatory = $true)][string]$Notice, [Parameter(Mandatory = $true)][string]$Owner, [Parameter(Mandatory = $true)][scriptblock]$Detail)
    return [pscustomobject]@{ path = @($Path); tempPrefix = $TempPrefix; ledger = $Ledger; list = $List; label = $Label; notice = $Notice; owner = $Owner; detail = $Detail }
}

function Get-HordeDecisionNoticeTakenPath {
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine(([string[]]@(@($HordeHome) + @($Kind.path))))
}

function Read-HordeDecisionNoticeTaken {
    # The awaiting list of one kind: known { awaiting }, the empty list for no file, unknown for a file that does not hold
    # together (never a guess, never started over).
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome)
    return (Read-HordeTakenLedgerFile -Path (Get-HordeDecisionNoticeTakenPath -Kind $Kind -HordeHome $HordeHome) -What $Kind.ledger -Noun "notice")
}

function Get-HordeDecisionNoticeTakenNowMs {
    param([datetime]$Now)
    return [long]($Now.ToUniversalTime() - [datetime]"1970-01-01T00:00:00Z").TotalMilliseconds
}

function Add-HordeDecisionNoticeTaken {
    # A notice about to be posted, onto the awaiting list and the file, once: { ok; reason; lines }. A notice already there (the
    # same id sent again after a crash) keeps its own clock and its alarm. The oldest mark past the list's size is given up WITH
    # a line in capitals. ok is $false when the file cannot be read or written: the caller must then not post.
    # -Answer is the entry's number: a routed answer's record, or the doorbell's count of answers in the set.
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId, [Parameter(Mandatory = $true)][long]$Answer, [string]$SessionId = "", [Parameter(Mandatory = $true)][datetime]$Now)
    $lines = @()
    $r = Read-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome
    if ($r.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = ($Kind.ledger + " cannot be read: " + $r.reason); lines = $lines } }
    $ledger = [pscustomobject]@{ awaiting = @($r.value.awaiting) }
    $session = $(if ($SessionId -cmatch '\A[A-Za-z0-9._:-]{1,128}\z') { $SessionId } else { "" })
    $entry = [pscustomobject]@{ messageId = $NoticeId.Replace("-", ""); messengerId = $NoticeId; postedMs = (Get-HordeDecisionNoticeTakenNowMs -Now $Now); from = $script:HordeDecisionNoticeTakenFrom; seq = $Answer; alarmed = $false; woken = $false; session = $session }
    if ($null -ne (Get-HordeChatTakenEntry -State $ledger -MessageId $entry.messageId)) { return [pscustomobject]@{ ok = $true; reason = ""; lines = $lines } }
    $overflow = @(Get-HordeChatTakenOverflow -State $ledger)
    [void](Add-HordeChatTaken -State $ledger -Entry $entry)
    try { Write-HordeTakenLedgerFile -Path (Get-HordeDecisionNoticeTakenPath -Kind $Kind -HordeHome $HordeHome) -Ledger $ledger -TempPrefix $Kind.tempPrefix }
    catch { return [pscustomobject]@{ ok = $false; reason = ($Kind.ledger + " could not be written: " + $_.Exception.Message); lines = $lines } }
    $lines = @(foreach ($old in $overflow) { "ALARM: " + $Kind.notice + " " + $old.messengerId + " (" + (& $Kind.detail $old) + ") left the awaiting list because it is full; it is no longer watched, but it may still be in " + $Kind.owner + " mailbox and be taken" })
    return [pscustomobject]@{ ok = $true; reason = ""; lines = $lines }
}

function Remove-HordeDecisionNoticeTaken {
    # A notice's mark off the list and the file (a post the messenger refused, so the notice is in no mailbox): { ok; reason }.
    # A notice not listed is already as wanted. Never throws.
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId)
    $r = Read-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome
    if ($r.state -cne "known") { return [pscustomobject]@{ ok = $false; reason = $Kind.ledger + " cannot be read: " + $r.reason } }
    $id = $NoticeId.Replace("-", "")
    $keep = @(@($r.value.awaiting) | Where-Object { $e = ConvertFrom-HordeChatTakenMark -Mark $_; $null -eq $e -or $e.messageId -cne $id })
    if ($keep.Count -eq @($r.value.awaiting).Count) { return [pscustomobject]@{ ok = $true; reason = "" } }
    try { Write-HordeTakenLedgerFile -Path (Get-HordeDecisionNoticeTakenPath -Kind $Kind -HordeHome $HordeHome) -Ledger ([pscustomobject]@{ awaiting = $keep }) -TempPrefix $Kind.tempPrefix }
    catch { return [pscustomobject]@{ ok = $false; reason = $Kind.ledger + " could not be written: " + $_.Exception.Message } }
    return [pscustomobject]@{ ok = $true; reason = "" }
}

function Invoke-HordeDecisionNoticeTakenTick {
    # Ask about every awaiting notice that is due and act (Get-HordeChatTakenAction, as the chat does): { lines; delivered;
    # alarmed; waiting; failed }. -Messenger is the one the notices were posted through ($null when none can be had now: the
    # clock alone then speaks). -Memory is the caller's table, kept between passes (when each mark was last asked). Never
    # throws; a list that cannot be read is said and left as it is.
    param([Parameter(Mandatory = $true)]$Kind, [Parameter(Mandatory = $true)][string]$HordeHome, $Messenger, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][double]$AlarmSeconds, [Parameter(Mandatory = $true)][double]$AfterAlarmSeconds, [double]$TtlSeconds = 604800, [hashtable]$Memory = $null)
    $lines = New-Object System.Collections.ArrayList
    $none = { param($Failed) return [pscustomobject]@{ lines = @($lines.ToArray()); delivered = 0; alarmed = 0; waiting = 0; failed = [bool]$Failed } }
    if ($null -eq $Memory) { $Memory = @{} }
    $r = Read-HordeDecisionNoticeTaken -Kind $Kind -HordeHome $HordeHome
    if ($r.state -cne "known") { [void]$lines.Add($Kind.label + ": " + $Kind.list + " cannot be read: " + $r.reason); return (& $none $true) }
    $awaiting = @($r.value.awaiting)
    if ($awaiting.Count -eq 0) { return (& $none $false) }
    $nowMs = Get-HordeDecisionNoticeTakenNowMs -Now $Now
    # Every pass asks every mark that is due: the caller spaces the passes, so the alarmed marks are
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
        if ($null -eq $e) { [void]$lines.Add($Kind.label + ": an awaiting mark that is not one was dropped"); $changed = $true; continue }
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
        $name = $Kind.notice + " " + $e.messengerId + " (" + (& $Kind.detail $e) + ")"
        switch ($act) {
            "wait" {
                if ($e.alarmed -and -not $wasAlarmed) { $changed = $true; $saved = ConvertTo-HordeChatTakenMark -Entry $e; [void]$keep.Add($saved) } else { [void]$keep.Add($mark) }
            }
            "confirmed" {
                $changed = $true; $delivered++
                $Memory["delivered-" + $e.messengerId] = $true
                [void]$lines.Add("TAKEN: " + $name + " was taken by " + $Kind.owner + " own session after " + [int]$age + " s" + $(if ($e.alarmed) { ", after the alarm" } else { "" }) + ": delivered")
            }
            "held" { $changed = $true; [void]$lines.Add("ALARM: " + $name + " NOT DELIVERED: the messenger holds it for good; it is no longer watched") }
            "expired" { $changed = $true; [void]$lines.Add("ALARM: " + $name + " NOT DELIVERED, given up after " + [int]$age + " s; it is no longer watched, but it may still be in " + $Kind.owner + " mailbox") }
            "alarm" {
                $changed = $true; $alarmed++
                $e.alarmed = $true
                $Memory["alarmed-" + $e.messageId] = $true
                [void]$keep.Add((ConvertTo-HordeChatTakenMark -Entry $e))
                [void]$lines.Add("ALARM: " + $name + " was NOT TAKEN by " + $Kind.owner + " session in " + [int]$age + " s (the wake is the wake watcher's, core/Wake.ps1); it stays in " + $Kind.owner + " mailbox and is asked about until it is taken")
            }
        }
    }
    if ($changed) {
        try { Write-HordeTakenLedgerFile -Path (Get-HordeDecisionNoticeTakenPath -Kind $Kind -HordeHome $HordeHome) -Ledger ([pscustomobject]@{ awaiting = @($keep.ToArray()) }) -TempPrefix $Kind.tempPrefix }
        catch { [void]$lines.Add($Kind.label + ": " + $Kind.list + " could not be written: " + $_.Exception.Message + "; it is read again on the next pass"); return (& $none $true) }
    }
    $result = & $none $false
    $result.delivered = $delivered
    $result.alarmed = $alarmed
    $result.waiting = $keep.Count
    return $result
}
