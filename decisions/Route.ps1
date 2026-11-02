# decisions/Route.ps1 - a founder's answer goes, by code, to the seat of whoever asked the question.
#
# WHY (the audit of 2026-10-16, findings 5, 6, 9 and 26). The bell (decisions/Notify.ps1) tells only the
# warchief's seat that the founder answered, with question numbers. The warchief then read who asked and
# relayed each answer by hand; an answer printed and not relayed showed as read and never rang again,
# so the asking Orc waited with no signal. Answered questions stayed open until the warchief remembered
# to close them: on 2026-10-13 the list showed 28 open, about ten of them settled long before. This file
# is that relay, done by code:
#   1. ROUTED: each answer of the founder's under an open question - one message-said record of his, from
#      ANY route (his phone, the window, words the warchief recorded from chat), since all of them are
#      records of one store - is sent to the seat of whoever asked (decisions/Rules.ps1,
#      Get-HordeDecisionAsker), with the question's number and title, his words and how they arrived.
#      One line goes to the fleet analyst (horde analyst mail), so a decision reaches the analyst and the
#      progress log without anyone remembering to tell it.
#   2. REMINDED ONCE: a question whose answer stands, routed, and still open after the setting
#      decisions.answers.unclosedMinutes (60) is flagged by the list itself (Get-HordeDecisionUnclosed),
#      and its asker is sent ONE reminder for that answer.
#   3. ACKNOWLEDGED: the asker closes the question with `horde decisions ack <number> -Answer <record>`,
#      which the notice names; that is the operation ack, and the rules' (Step-HordeDecisionAcked).
#
# SENT IS NOT DELIVERED (T-0391, decisions/RouteTaken.ps1). The messenger accepting the notice puts it in the Orc's
# mailbox; it does not prompt the session. So the route record below means SENT, and the notice is on an awaiting
# list from the moment it is accepted: it is DELIVERED only when the Orc's own session took it (the messenger's
# status says handed-over or seen), one ALARM line is raised when it is not taken in takenAlarmSeconds, and it is
# never dropped. The pass asks the awaiting list first, before it reads the store.
#
# EXACTLY ONCE, AND PROVEN. What was sent is a record of the store (answer-routed: to whom, whether askedBy
# could be resolved, the notice's id, what the analyst was told), written only after the messenger took
# the notice, and the rules apply one per answer and purpose. So:
#   - a router restarted reads the store and sends nothing already recorded;
#   - an answer the relay applied again is the SAME record (answered from its id), so nothing new is
#     there to route; a NEW answer (he changed his words) is a new record and is routed;
#   - a crash between the messenger taking the notice and the record being written leaves the answer
#     unrouted in the store, and the next pass posts THE SAME notice: its id is made from the home, the
#     purpose, the question, the answer and the seat (Get-HordeDecisionRouteNoticeId), and a messenger
#     that offers idempotent.post keeps one message per id. The analyst's line is looked for by its own
#     token before it is written again (Send-HordeDecisionRouteAnalyst);
#   - two routers at once (the relay runner's turn and a person's `horde decisions route`) cannot both
#     send: one per home holds a named mutex for its pass, as the bell does, and the store refuses the
#     second record of an answer.
# WHERE IT GOES, NEVER A GUESS. "Orc C" is the session whose fleet record wears label C with the role orc,
# proven still there (core/SessionSeat.ps1, Get-HordeLabelSeat: the same checks the warchief's seat is
# held to). A question the warchief asked goes to the warchief's seat. Anything else - askedBy that names
# nobody, an Orc whose seat cannot be found or proven - goes to the warchief instead, and the record says
# so (resolved false, and the note says why): the answer is never dropped and never sent to a seat picked
# by a label that only looks right. When even the warchief's seat cannot be had, nothing is sent and
# nothing recorded, and the next pass tries again: the answer waits in the store.
# ROUTING IS NOT AUTHORIZING. The notice is a copy of words already in the store, for the asker to act
# on; it says that the list is the authority and that it authorizes nothing. It touches no check of a
# question that needs a passkey.
#
# THE HOME IS NAMED IN THE COMMANDS (T-0263, live defect of 2026-10-17: Orcs B and D were routed answers 79,
# 80 and 63, ran `horde decisions show 79` in their own default HORDE_HOME and were told the question
# does not exist, so they refused to acknowledge). The store is <HORDE_HOME>\store\decisions, and the
# relay runner's home is not an Orc's. So the notice carries the show and ack commands with the home of
# the store that holds the question, as `-HordeHome '<path>'` (alias -Home), which horde decisions show,
# ack and close take and which overrides HORDE_HOME for that one call (cli/commands/decisions.ps1): one line
# that is the same in PowerShell 5.1 and 7, with no environment to set and put back
# (Format-HordeDecisionRouteCommand). The path is single-quoted with PowerShell's own escaper, so that a
# curly quote (U+2018 to U+201B, which PowerShell also ends a string on) cannot end it. WHY THIS
# AND NOT A POINTER the router leaves in the default home: a pointer is state that outlives the thing it
# points at and can send `show` to the wrong store without a word; the command in the notice is
# stateless, names the store it came from, and is right for the notice it is in.
#
# THE FOUNDER, VERIFIED - OR ONLY HIS LABEL (T-0264, live defect of 2026-10-17: Orc D saw a routed answer
# as "from OUTSIDE THE FLEET, sender calls itself F (not verified)"). The router is a service of the relay
# runner, not a session: it posts through the wezfleet messenger as `mail post` (not `tell`), with
# -FromSessionId only when from.sessionId is a session uuid (here it is the word horde-decisions-route, so
# none) and -FromLabel F, and without -FromVerified because from.verified was never set. wezfleet shows a
# mail with no verified sender and no session as from outside the fleet. The bell had the same defect and
# fixed it on 2026-10-12 (decisions/Notify.ps1, THE FOUNDER, VERIFIED); routing now asks the same rule,
# for the one answer a notice carries: from.verified = founder, passkey, key id ONLY when the answer's
# record names the passkey the relay verified (route phone, evidence, signedBy) AND that passkey is
# trusted now AND the question still has the wording he answered (PR 333 review: an open question can be
# reworded after the answer, and his passkey signed his words against the wording he saw; a verified
# line over another wording would vouch for a pairing he never saw). An answer typed in the window or
# recorded from chat, a record from before records named the passkey, a revoked key, a trust store that
# cannot say, a reworded question: the notice is NOT verified, and the pass line says why.
# WHO THE POSTER IS. The poster is Horde's router, not F and not the founder. A notice that is not
# verified is therefore posted as the reserved system sender (from.system "horde", messengers/Port.ps1),
# so wezfleet shows "the sender calls itself: horde (not verified)", which is true. A verified notice
# needs a hub label beside it (wezfleet's rule) and shows the founder banner in its place, so the setting
# fromLabel (F) is used there only. The trust store asked is the router's own home's: the relay runner
# that wrote signedBy verified the signature against that same store, and any other home fails safe
# (the answer goes unverified). Wording and trust are judged on the list read at the start of the pass: a
# reword, or a revocation, that lands in the seconds between that read and the post still goes out as
# verified. That window is as long as one pass and is accepted; the list stays the authority.
#
# HOW OLD AN ANSWER MAY BE and still be sent is the setting decisions.answers.routeWithinHours (48):
# answers given before routing existed, or while nothing ran it, are not sent days late on its first
# pass; the list still flags their questions while they stay open.
#
# WHO TURNS IT: the relay runner's decisions channel, each tick, beside the bell (channels/decisions;
# the runner is the process that is always there), and `horde decisions route` for one pass by hand. A
# pass reads the store only when it changed or the setting passSeconds (60) has passed, which is what
# the hour flag needs.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Operations.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\SessionSeat.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Device.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\TextUuid.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "messengers\Port.ps1")
# The one rule for naming the founder as a verified sender (Get-HordeDecisionNotifyVerified) and the
# trust store it asks: routing reuses the bell's rule and does not write a second one.
. (Join-Path $PSScriptRoot "Notify.ps1")
# A notice the messenger accepted is delivered only on the Orc's own TAKEN (T-0391; RouteTaken.ps1).
. (Join-Path $PSScriptRoot "RouteTaken.ps1")
# Every messenger, at script level, as decisions/Notify.ps1 loads them; one already registered is not
# loaded again, because a second registration is refused.
foreach ($routeMessengerFile in @(Get-HordeMessengerFiles)) {
    if (@(Get-HordeMessengerNames) -cnotcontains (Split-Path -Leaf (Split-Path -Parent $routeMessengerFile))) { . $routeMessengerFile }
}

# What a messenger must offer to carry the notice: the bell's own list, for the bell's reasons
# (decisions/Notify.ps1): never typed, one message per id, and a knock that wakes an idle session.
$script:HordeDecisionRouteMessengerNeeds = @("body.untyped", "idempotent.post", "wake")
$script:HordeDecisionRouteModule = "decisions-route"
$script:HordeDecisionRouteSettings = New-HordeModuleSettings -Module $script:HordeDecisionRouteModule -Settings @(
    @{ name = "passSeconds"; kind = "whole"; default = 60; min = 5; max = 3600; what = "How often the store is read for answers to route and questions to flag when nothing in it changed, in seconds." }
    @{ name = "seatGraceSeconds"; kind = "whole"; default = 300; min = 0; max = 3600; what = "How long an answer waits for an Orc seat that cannot be proven just now before it goes to the warchief, in seconds." }
    @{ name = "takenAlarmSeconds"; kind = "whole"; default = 90; min = 10; max = 3600; what = "How long a routed notice the messenger accepted may wait to be taken by the Orc's own session before one ALARM line is raised and the notice is kept awaiting, in seconds." }
    @{ name = "takenAfterAlarmSeconds"; kind = "whole"; default = 300; min = 5; max = 3600; what = "How often a routed notice already alarmed is asked about, until it is taken, in seconds." }
    @{ name = "fromLabel"; kind = "label"; default = "F"; what = "The hub label wezfleet needs beside a VERIFIED routed answer (it shows the founder banner instead of the label). An answer that is not verified is posted as Horde itself, the reserved sender horde." }
)
# Who the notice is from: the router is no session, so it names itself, as the bell does.
$script:HordeDecisionRouteFrom = "horde-decisions-route"
# How long a notice may wait in a mailbox: the link's most, 7 days, as the bell's.
$script:HordeDecisionRouteTtlSeconds = 604800
$script:HordeDecisionRouteStages = @("accepted", "handed-over", "seen")
# The most of his words, and of a title, the analyst's one line carries.
$script:HordeDecisionRouteAnalystChars = 300
# When each answer's Orc seat was first found UNPROVABLE (not absent), by purpose, question and answer: the
# grace before it falls back to the warchief runs from here (review of 2026-10-16, finding 1). It lives as
# long as the router does; a router that starts again starts the grace again, which only waits longer.
$script:HordeDecisionRouteUnknownSince = @{}

function Get-HordeDecisionRouteSettingsDeclaration { return $script:HordeDecisionRouteSettings }

function Get-HordeDecisionRouteSettings {
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeDecisionRouteSettings -HordeHome $HordeHome)
}

function Get-HordeDecisionRouteNoticeId {
    # The notice's id (header, EXACTLY ONCE): the same home, purpose, question, answer and seat always
    # make the same id, so a send repeated after a crash is one message to a messenger that keeps ids.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [string]$Purpose, [int]$Number, [long]$Answer, [string]$SessionId)
    $key = "horde-decisions-route`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant() + "`n" + $Purpose + "`n" + $Number + "`n" + $Answer + "`n" + $SessionId
    return (ConvertTo-HordeTextUuid -Text $key)
}

function Get-HordeDecisionRouteRecordId {
    # The store id of the record that says an answer was routed: made from the purpose, the question and
    # the answer alone, so that every router of this store asks for the same record, and the store
    # answers the second from the first.
    param([string]$Purpose, [int]$Number, [long]$Answer)
    return ((ConvertTo-HordeTextUuid -Text ("horde-decisions-route record`n" + $Purpose + "`n" + $Number + "`n" + $Answer)) -replace "-", "")
}

function ConvertFrom-HordeDecisionRouteTime {
    # A stored time as UTC, or $null when it is not one.
    param([string]$Text)
    $stamp = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$stamp)) { return $stamp }
    return $null
}

function Test-HordeDecisionRouted {
    # Does a view's routes hold a record for -Answer and -Purpose?
    param($Question, [long]$Answer, [string]$Purpose)
    if ($null -eq $Question.PSObject.Properties["routes"]) { return $false }
    return (@($Question.routes | Where-Object { [long]$_.answer -eq $Answer -and "$($_.purpose)" -ceq $Purpose }).Count -gt 0)
}

function Get-HordeDecisionRouteClosedWork {
    # PURE. The one closing notice a question is due, as { purpose = "closed"; question; answer; why }, or $null. Due
    # when the warchief closed it (closed, and not by an acknowledgement), an Orc asked it, no closing notice was
    # recorded, it closed within -WithinHours, and either its Orc never replied to the founder's change
    # (the view's warchiefClosedUnreplied) or all he said was chat words under a question that needs a passkey
    # (or some part of it was only chat words). ONLY A CLOSE PROVEN FROM THE WARCHIEF'S SEAT IS TOLD AS HIS (review of
    # PR 335, round 4, M1): the view's closedByWarchief must be set, which the close record carries only when the
    # command line proved the seat. Any other session's close tells nobody that "the warchief closed" anything: the
    # Orc is not sent a notice at all (the smallest honest choice; the list still shows the close and its outcome).
    # answer is the newest of his records made while it was open: the record the notice is kept against.
    param($Question, [datetime]$Now, [int]$WithinHours)
    $q = $Question
    if ("$($q.state)" -cne "closed" -or ($null -ne $q.PSObject.Properties["closedBy"] -and "$($q.closedBy)" -ne "") -or $null -eq $q.thread.PSObject.Properties["messages"]) { return $null }
    if (-not ($null -ne $q.PSObject.Properties["closedByWarchief"] -and [bool]$q.closedByWarchief)) { return $null }
    if ((Get-HordeDecisionAsker -AskedBy "$($q.askedBy)").seat -cne "orc") { return $null }
    $at = ConvertFrom-HordeDecisionRouteTime -Text "$($q.closedAt)"
    if ($null -eq $at -or $at -lt $Now.ToUniversalTime().AddHours(-$WithinHours)) { return $null }
    $his = @($q.thread.messages | Where-Object { $null -ne $_ -and "$($_.speaker)" -ceq (Get-HordeDecisionFirstTurn) -and "$($_.act)" -eq "" -and -not ($null -ne $_.PSObject.Properties["arrivedAfterClosing"] -and [bool]$_.arrivedAfterClosing) })
    if ($his.Count -eq 0) { return $null }
    $unreplied = ($null -ne $q.PSObject.Properties["warchiefClosedUnreplied"] -and [bool]$q.warchiefClosedUnreplied)
    $wordsOnly = ($null -ne $q.PSObject.Properties["needsPasskey"] -and [bool]$q.needsPasskey -and @($his | Where-Object { -not ($null -ne $_.PSObject.Properties["notPasskey"] -and [bool]$_.notPasskey) }).Count -eq 0)
    # N3: a question in parts where one part was signed and another got only chat words never completed: the Orc that
    # waited on the unsigned part is told as well (why = "parts").
    # S2 (review of PR 335, round 5): a SIGNED answer to the WHOLE question (no part named) answers every part, so it
    # takes this notice away; only an answer to one part, or none, leaves a part without a passkey answer.
    $wholeSigned = (@($his | Where-Object { [bool]$_.asks -and "$($_.part)" -eq "" -and -not ($null -ne $_.PSObject.Properties["notPasskey"] -and [bool]$_.notPasskey) }).Count -gt 0)
    $partsUnsigned = (-not $wordsOnly -and -not $wholeSigned -and $null -ne $q.PSObject.Properties["needsPasskey"] -and [bool]$q.needsPasskey -and $null -ne $q.thread.PSObject.Properties["parts"] -and @($q.thread.parts | Where-Object { -not [bool]$_.answered }).Count -gt 0 -and @($his | Where-Object { $null -ne $_.PSObject.Properties["notPasskey"] -and [bool]$_.notPasskey }).Count -gt 0)
    if (-not $unreplied -and -not $wordsOnly -and -not $partsUnsigned) { return $null }
    $last = $his[$his.Count - 1]
    if (Test-HordeDecisionRouted -Question $q -Answer ([long]$last.sequence) -Purpose "closed") { return $null }
    return [pscustomobject]@{ purpose = "closed"; question = $q; answer = $last; why = $(if ($unreplied) { "unreplied" } elseif ($partsUnsigned) { "parts" } else { "words" }) }
}

function Get-HordeDecisionRouteWork {
    # PURE. What a pass has to send, from a list result read with every question and its messages:
    # { purpose; question; answer } for each answer of the founder's under an open question, no older than
    # -WithinHours, that has no answer-routed record yet; then each flagged question (the list's
    # unclosed) whose standing answer was routed and has had no reminder. In store order.
    param([Parameter(Mandatory = $true)]$List, [datetime]$Now, [int]$WithinHours)
    $work = New-Object System.Collections.ArrayList
    $oldest = $Now.ToUniversalTime().AddHours(-$WithinHours)
    $byNumber = @{}
    foreach ($q in @($List.questions)) {
        if ($null -eq $q) { continue }
        $byNumber[[int]$q.number] = $q
        # THE WARCHIEF CLOSED AN ORC'S QUESTION (review of PR 335, S3): over a change its Orc never replied to, or
        # over chat words only under a question that needs a passkey. The Orc is told once, whatever it waits for.
        $told = Get-HordeDecisionRouteClosedWork -Question $q -Now $Now -WithinHours $WithinHours
        if ($null -ne $told) { [void]$work.Add($told); continue }
        if ("$($q.state)" -cne "open" -or $null -eq $q.thread.PSObject.Properties["messages"]) { continue }
        foreach ($m in @($q.thread.messages)) {
            if ($null -eq $m -or "$($m.speaker)" -cne (Get-HordeDecisionFirstTurn) -or "$($m.act)" -ne "") { continue }
            $at = ConvertFrom-HordeDecisionRouteTime -Text "$($m.at)"
            if ($null -eq $at -or $at -lt $oldest) { continue }
            if (Test-HordeDecisionRouted -Question $q -Answer ([long]$m.sequence) -Purpose "answer") { continue }
            [void]$work.Add([pscustomobject]@{ purpose = "answer"; question = $q; answer = $m })
        }
    }
    if ($null -ne $List.PSObject.Properties["unclosed"]) {
        foreach ($u in @($List.unclosed)) {
            if ($null -eq $u -or [bool]$u.reminded -or -not $byNumber.ContainsKey([int]$u.number)) { continue }
            $q = $byNumber[[int]$u.number]
            if (-not (Test-HordeDecisionRouted -Question $q -Answer ([long]$u.answer) -Purpose "answer")) { continue }
            $m = @($q.thread.messages | Where-Object { [long]$_.sequence -eq [long]$u.answer }) | Select-Object -First 1
            if ($null -eq $m) { continue }
            [void]$work.Add([pscustomobject]@{ purpose = "nudge"; question = $q; answer = $m; flag = ("$($u.line)" -replace '\Aquestion [0-9]+: ', '') })
        }
    }
    return @($work | Sort-Object { [long]$_.answer.sequence }, { $_.purpose })
}

function Get-HordeDecisionRouteOneLine {
    # Text from outside this file (a seat reader's reason, an exception's message) as one line: a line
    # break in it could start a line of the notice with the marker of a command (PR 333 second review).
    param([string]$Text)
    return ([regex]::Replace($Text, '[\r\n]+', ' ').Trim())
}

function Resolve-HordeDecisionRouteTarget {
    # Where one answer goes (header, WHERE IT GOES): { ok; seat; label; sessionId; resolved; note; problem }.
    # ok $false, with the problem, only when even the warchief's seat cannot be had. -Seat answers, for a
    # role and a label ("" for a seat by role alone), a core/Tristate.ps1 answer whose known value has
    # sessionId: core/SessionSeat.ps1's two readers, or a test's stand-in.
    param([Parameter(Mandatory = $true)]$Question, [Parameter(Mandatory = $true)][scriptblock]$Seat)
    $asker = Get-HordeDecisionAsker -AskedBy "$($Question.askedBy)"
    $note = ""
    $seatState = ""
    $seatWhy = ""
    if ($asker.seat -ceq "orc") {
        $found = $null
        try { $found = & $Seat "orc" $asker.label } catch { $found = New-HordeUnknown -Reason $_.Exception.Message }
        if ($null -ne $found -and "$($found.state)" -ceq "known" -and "$($found.value.sessionId)" -ne "") {
            return [pscustomobject]@{ ok = $true; seat = "orc"; label = $asker.label; sessionId = "$($found.value.sessionId)"; resolved = $true; note = ""; problem = ""; seatState = "known"; asker = $asker.seat }
        }
        # ABSENT is a seat that is plainly not there; anything else (unknown, a reader that threw, no
        # answer) is a seat that cannot be proven NOW, which the pass waits out before it falls back.
        $seatState = $(if ($null -ne $found -and "$($found.state)" -ceq "absent") { "absent" } else { "unknown" })
        $why = $(if ($null -eq $found) { "nothing answered" } elseif ("$($found.reason)" -ne "") { Get-HordeDecisionRouteOneLine -Text "$($found.reason)" } else { "no live session wears its label with the role orc" })
        $seatWhy = $why
        $note = $asker.shown + "'s seat could not be found (" + $why + "), so the answer went to the warchief instead"
    }
    elseif ($asker.seat -cne "warchief") { $note = $asker.why + "; it went to the warchief instead" }
    $boss = $null
    try { $boss = & $Seat "warchief" "" } catch { $boss = New-HordeUnknown -Reason $_.Exception.Message }
    if ($null -eq $boss -or "$($boss.state)" -cne "known" -or "$($boss.value.sessionId)" -eq "") {
        $why = $(if ($null -eq $boss) { "nothing answered" } elseif ("$($boss.reason)" -ne "") { Get-HordeDecisionRouteOneLine -Text "$($boss.reason)" } else { "no live session holds the role" })
        $lead = $(if ($note -ne "") { $note + ", and " } else { "" })
        return [pscustomobject]@{ ok = $false; seat = ""; label = ""; sessionId = ""; resolved = $false; note = $note; problem = ($lead + "the warchief's seat cannot be had: " + $why); seatState = $seatState; seatWhy = $seatWhy; asker = $asker.seat }
    }
    return [pscustomobject]@{ ok = $true; seat = "warchief"; label = ""; sessionId = "$($boss.value.sessionId)"; resolved = ($note -eq ""); note = $note; problem = ""; seatState = $seatState; seatWhy = $seatWhy; asker = $asker.seat }
}

function Format-HordeDecisionRouteCommand {
    # One horde command as one line (header, THE HOME IS NAMED IN THE COMMANDS): the command with
    # -HordeHome '<path>' after it, which overrides HORDE_HOME for that one call. The path goes through
    # PowerShell's own escaper for single-quoted content, which doubles every character PowerShell
    # treats as a single quote (the ASCII one and U+2018 to U+201B); inside single quotes $ and spaces are
    # inert. With no home the command is returned as it is.
    param([Parameter(Mandatory = $true)][string]$Command, [string]$HordeHome = "")
    if ($HordeHome -eq "") { return $Command }
    $quoted = "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($HordeHome) + "'"
    return ($Command + " -HordeHome " + $quoted)
}

function Get-HordeDecisionRouteStoreHome {
    # The HORDE_HOME whose store is -StoreRoot (<home>\store\decisions), for the commands in a notice. A
    # router given no store root reads the home's own, so the answer is -HordeHome; a root that is not of
    # that shape cannot be named by a home, and -HordeHome is the nearest thing that can be said.
    param([string]$StoreRoot = "", [Parameter(Mandatory = $true)][string]$HordeHome)
    if ($StoreRoot -eq "") { return $HordeHome }
    $full = [System.IO.Path]::GetFullPath($StoreRoot).TrimEnd('\')
    $store = Split-Path -Parent $full
    if ($store -ne "" -and (Split-Path -Leaf $full) -ieq "decisions" -and (Split-Path -Leaf $store) -ieq "store") { return (Split-Path -Parent $store) }
    return $HordeHome
}

function Get-HordeDecisionRouteWording {
    # Whether the question was reworded since the answer was given: { differs; answered; now }. differs is
    # true when the wording the answer records is not the question's current one. A record that states no
    # wording (words recorded from chat) is read as the current one for the notice's remark, but it is
    # never verified anyway (no passkey signs it).
    param([Parameter(Mandatory = $true)]$Item)
    $answered = [int]$Item.answer.wordingVersion
    $now = [int]$Item.question.wordingVersion
    return [pscustomobject]@{ differs = ($answered -ne $now); answered = $answered; now = $now; stated = [bool]$Item.answer.wordingStated }
}

function Format-HordeDecisionRouteClosedNotice {
    # The notice that the warchief closed an Orc's question: the first line says so in the outcome's own
    # words (cut to one line), then why the Orc is told, then the warchief's words and his, each as quoted
    # lines (a line of either that starts like a command is still only a quoted line), and the list as authority.
    param([Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)]$Target, [string]$HordeHome = "")
    $q = $Item.question
    $number = [int]$q.number
    $outcome = "$($q.outcome)"
    $lines = New-Object System.Collections.ArrayList
    $quote = "> "
    [void]$lines.Add("The warchief closed question " + $number + ": " + (Get-HordeDecisionRouteOneLine -Text $outcome))
    if (-not ($Target.seat -ceq "orc")) { [void]$lines.Add("This is for " + (Get-HordeDecisionAsker -AskedBy "$($q.askedBy)").shown + ", who asked it; its seat could not be found, so it came to you.") }
    [void]$lines.Add("Question " + $number + ": " + $q.title)
    if ("$($Item.why)" -ceq "unreplied") { [void]$lines.Add("The founder changed his answer and you had not said what became of your work, so the warchief closed it without that reply. If you had acted on his first answer, ask the warchief whether it needs undoing.") }
    elseif ("$($Item.why)" -ceq "parts") { [void]$lines.Add("Some part of this question has no passkey answer from him, and it needs a passkey: none will be routed now that it is closed. Any chat words he said are below; the list shows which parts he signed.") }
    else { [void]$lines.Add("All he said was chat words, and this question needs a passkey: no passkey answer came, and none will be routed now that it is closed.") }
    [void]$lines.Add("The warchief's words (the outcome):")
    foreach ($l in @($outcome -split "\r\n|\r|\n")) { [void]$lines.Add($quote + $l) }
    [void]$lines.Add("His last words (record " + [long]$Item.answer.sequence + ", " + $Item.answer.routeShown + ", " + $Item.answer.at + "):")
    foreach ($l in @(([string]$Item.answer.text) -split "\r\n|\r|\n")) { [void]$lines.Add($quote + $l) }
    [void]$lines.Add("The list is the authority; read it with:")
    [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions show " + $number) -HordeHome $HordeHome))
    [void]$lines.Add("This copy authorizes nothing.")
    return ($lines -join "`r`n")
}

function Format-HordeDecisionRouteNotice {
    # The notice's body: plain lines, the question's number and title, who answered and by what route,
    # his words whole, what to do, and that it authorizes nothing (header, ROUTING IS NOT AUTHORIZING).
    # -HordeHome is the home of the store that holds the question; the commands name it.
    param([Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)]$Target, [string]$HordeHome = "")
    $q = $Item.question
    $m = $Item.answer
    $number = [int]$q.number
    $seq = [long]$m.sequence
    $lines = New-Object System.Collections.ArrayList
    $part = $(if ("$($m.part)" -ne "") { " (part " + $m.part + ")" } else { "" })
    $mine = ($Target.seat -ceq "orc")
    # A CHANGED ANSWER (decisions/Rules.ps1, THE FOUNDER CHANGES HIS ANSWER) is routed like any answer of his,
    # verified on the same terms; the notice says it is a change, with the OLD and the NEW words and the time,
    # and gives the asking Orc the command that says what became of its work.
    $changed = ($null -ne $m.PSObject.Properties["changedFrom"] -and [long]$m.changedFrom -ge 1)
    # WORDS THAT ARE NOT A PASSKEY ANSWER (decisions/Rules.ps1, A QUESTION THAT NEEDS A PASSKEY): his words recorded
    # from chat under a question that needs a passkey are routed and said plainly to be no answer to it.
    $unsigned = ($null -ne $m.PSObject.Properties["notPasskey"] -and [bool]$m.notPasskey)
    $headWords = $(if ($unsigned) { "FOUNDER'S CHAT WORDS, NOT A PASSKEY ANSWER" } elseif ($changed) { "FOUNDER CHANGED HIS ANSWER" } else { "FOUNDER ANSWER" })
    if ($Item.purpose -ceq "closed") { return (Format-HordeDecisionRouteClosedNotice -Item $Item -Target $Target -HordeHome $HordeHome) }
    if ($Item.purpose -ceq "nudge") {
        [void]$lines.Add("UNCLOSED QUESTION " + $number + ": " + $Item.flag + ". This is the one reminder for this answer.")
    }
    elseif ($mine -or ($Target.resolved -and $Target.seat -ceq "warchief")) {
        [void]$lines.Add($headWords + " to your question " + $number + $part + ", routed to you by Horde.")
    }
    else {
        [void]$lines.Add($headWords + " to question " + $number + $part + ", asked by '" + $q.askedBy + "', sent to you, the warchief: " + $Target.note + ".")
    }
    $wording = Get-HordeDecisionRouteWording -Item $Item
    $reworded = ($wording.stated -and $wording.differs)
    [void]$lines.Add("Question " + $number + ": " + $q.title)
    # The list keeps only a question's current wording, so the one he answered cannot be shown; the
    # notice says so instead of letting the current title stand for it.
    if ($reworded) { [void]$lines.Add("NOTE: the question was reworded after he answered (he answered wording " + $wording.answered + ", it is now wording " + $wording.now + "). The title above is the CURRENT wording; the list does not keep the one he saw, so read his words as an answer to that earlier wording.") }
    [void]$lines.Add("Answered by the founder, " + "$($m.routeShown)" + " (record " + $seq + ", " + $m.at + ").")
    if ($unsigned) { [void]$lines.Add("THIS IS NOT A PASSKEY ANSWER. Question " + $number + " needs a passkey, and these words were recorded from chat: no passkey signed them. They are kept and shown, but they do not answer the question. It stays waiting for his answer on the phone; do not act on these words as his answer.") }
    # HIS WORDS GO WITH EVERY NOTICE, THE REMINDER TOO (review of 2026-10-16, finding 2): the reminder's
    # target is found again when it is sent, and an Orc that never received the answer (it went to the
    # warchief while the Orc's seat could not be proven) must not be told to acknowledge words unseen.
    if ($changed) {
        [void]$lines.Add("He CHANGED his answer at " + $m.at + ": record " + $seq + " replaces record " + $m.changedFrom + ". If you already acted on the first one, it may need undoing.")
        [void]$lines.Add("His OLD words (record " + $m.changedFrom + "):")
        foreach ($l in @(([string]$m.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add(("> " + $l)) }
        [void]$lines.Add("His NEW words (record " + $seq + "):")
    }
    else { [void]$lines.Add("His words:") }
    foreach ($l in @(([string]$m.text) -split "\r\n|\r|\n")) { [void]$lines.Add("> " + $l) }
    if ($unsigned) {
        [void]$lines.Add("A passkey answer, if he gives one before this question is closed, will be routed to you. Until then there is nothing to acknowledge: an acknowledgement of these words is refused.")
    }
    elseif ($changed -and $mine) {
        [void]$lines.Add("FIRST say what became of your work, with ONE of these (he is shown your reply in plain words, and sees 'waiting for Orc " + $Target.label + " to confirm' until you do). In PowerShell, with -HordeHome naming the founder's list:")
        [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions change-reply " + $number + " -Answer " + $seq + " -Reply not-acted") -HordeHome $HordeHome))
        [void]$lines.Add("     (you had not acted yet and are using the new answer)")
        [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions change-reply " + $number + " -Answer " + $seq + " -Reply undoing") -HordeHome $HordeHome))
        [void]$lines.Add("     (you had already acted on the first answer and are undoing it)")
        [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions change-reply " + $number + " -Answer " + $seq + " -Reply cannot-undo -Why 'why it cannot be undone, in one line'") -HordeHome $HordeHome))
        [void]$lines.Add("     (you had already acted and cannot undo it; say why)")
    }
    if ($unsigned) { }
    elseif ($mine) {
        [void]$lines.Add("When you have taken it, acknowledge it. That closes the question, with you as the closer" + $(if ($changed) { " (an acknowledgement is refused until you have run the change-reply above)" } else { "" }) + ". In PowerShell (the lines starting PS> are the commands; -HordeHome names the founder's list, which is not your own HORDE_HOME):")
        [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions ack " + $number + " -Answer " + $seq) -HordeHome $HordeHome))
    }
    else {
        if ($changed -and (Get-HordeDecisionAsker -AskedBy "$($q.askedBy)").seat -ceq "orc") { [void]$lines.Add("A changed answer is closed over only after the Orc that asked has said what became of its work (horde decisions change-reply " + $number + " -Answer " + $seq + " -Reply <not-acted, undoing or cannot-undo>); until then the Orc's own close is refused. The warchief can close it without the reply, with an outcome that says why.") }
        [void]$lines.Add("When it is dealt with, close it, with your own one line of outcome in place of the text in quotes. In PowerShell (the lines starting PS> are the commands; -HordeHome names the founder's list, which is not your own HORDE_HOME):")
        [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions close " + $number + " -Outcome 'what was done, in one line'") -HordeHome $HordeHome))
    }
    [void]$lines.Add("The list is the authority; read it with:")
    [void]$lines.Add("PS> " + (Format-HordeDecisionRouteCommand -Command ("horde decisions show " + $number) -HordeHome $HordeHome))
    [void]$lines.Add("This copy authorizes nothing: a question that needs a passkey is authorized only by its own check.")
    return ($lines -join "`r`n")
}

function Send-HordeDecisionRouteAnalyst {
    # The one line for the fleet analyst (horde analyst mail), unless a line with -Token is already in its
    # mail - waiting or delivered - from a send cut off before its record was written (header, EXACTLY
    # ONCE). { ok; said }. Loaded only when called: the analyst's files are no other caller's cost.
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Token, [string]$HordeHome = "", $Since = $null)
    $root = Split-Path -Parent $PSScriptRoot
    foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
    . (Join-Path $root "cli\AnalystTend.ps1")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    $policy = Get-HordeAnalystPolicy -HordeHome $HordeHome
    if (-not $policy.ok) { return [pscustomobject]@{ ok = $false; said = ("the analyst's settings are refused: " + $policy.reason) } }
    $folder = Get-HordeAnalystFolder -Values $policy.values -HordeHome $HordeHome
    $paths = Get-HordeAnalystPaths -Folder $folder
    foreach ($dir in @($paths.mail, $paths.delivered)) {
        if (-not [System.IO.Directory]::Exists($dir)) { continue }
        foreach ($file in @([System.IO.Directory]::GetFiles($dir, "*.txt"))) {
            if ($null -ne $Since -and [System.IO.File]::GetLastWriteTimeUtc($file) -lt ([datetime]$Since).AddMinutes(-5)) { continue }
            $held = ""
            try { $held = [System.IO.File]::ReadAllText($file) } catch { continue }
            if ($held.Contains($Token)) { return [pscustomobject]@{ ok = $true; said = ("already left for the analyst as " + [System.IO.Path]::GetFileName($file)) } }
        }
    }
    try { return [pscustomobject]@{ ok = $true; said = (Write-HordeAnalystMail -Folder $folder -Text $Text -Markers $policy.markers) } }
    catch { return [pscustomobject]@{ ok = $false; said = ("not left for the analyst: " + $_.Exception.Message) } }
}

function Format-HordeDecisionRouteAnalystLine {
    # The analyst's one line for a routed answer: fixed words, the question, his words' first line cut to
    # a stated length, where it went, and the token it is found by again.
    param([Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)]$Target, [Parameter(Mandatory = $true)][string]$Token)
    $cut = { param([string]$Text) $first = @(([string]$Text) -split "\r\n|\r|\n")[0]; if ($first.Length -gt $script:HordeDecisionRouteAnalystChars) { $first = $first.Substring(0, $script:HordeDecisionRouteAnalystChars) + "..." }; return $first }
    $why = $(if ($Target.resolved) { "" } elseif ("$($Target.asker)" -ceq "orc") { " (askedBy '" + $Item.question.askedBy + "' is clear, but that Orc's seat was not found)" } else { " (askedBy '" + $Item.question.askedBy + "' could not be resolved)" })
    $to = $(if ($Target.seat -ceq "orc") { "Orc " + $Target.label } else { "the warchief" + $why })
    $changedNote = $(if ($null -ne $Item.answer.PSObject.Properties["changedFrom"] -and [long]$Item.answer.changedFrom -ge 1) { " CHANGED HIS ANSWER (was: " + (& $cut ([string]$Item.answer.changedFromText)) + "), now" } else { "" })
    return ("DECISION: question " + $Item.question.number + " (" + (& $cut "$($Item.question.title)") + ") answered by the founder," + $changedNote + " " + $Item.answer.routeShown + " (record " + $Item.answer.sequence + "): " + (& $cut ([string]$Item.answer.text)) + " - sent to " + $to + ". " + $Token)
}

function Invoke-HordeDecisionRoutePass {
    # ONE PASS (header): read the list, send what is due, record each send. Returns { outcome; lines;
    # routed; pending }: outcome nothing, routed or pending; lines one plain line for each answer sent,
    # reminded or left pending; routed and pending how many. -Clock, -Seat and -Analyst are for a test
    # that hands in its own; -StoreRoot names a store that is not this home's own.
    param([scriptblock]$Clock = $null, [scriptblock]$Seat = $null, [scriptblock]$Analyst = $null, [string]$HordeHome = "", [string]$StoreRoot = "", [string]$FromLabel = "", [int]$SeatGraceSeconds = 300, [scriptblock]$Trust = $null, [int]$TakenAlarmSeconds = 90, [int]$TakenAfterAlarmSeconds = 300, [hashtable]$Memory = $null)
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Seat) { $Seat = { param([string]$Role, [string]$Label) if ($Label -ceq "") { return (Get-HordeRoleSeat -Role $Role) }; return (Get-HordeLabelSeat -Label $Label -Role $Role) } }
    if ($null -eq $Analyst) { $Analyst = { param([string]$Text, [string]$Token, $Since) return (Send-HordeDecisionRouteAnalyst -Text $Text -Token $Token -HordeHome $HordeHome -Since $Since) } }
    if ($null -eq $Trust) { $Trust = { param([string]$KeyId) return (Find-HordeRelayTrustedSender -HordeHome $HordeHome -KeyId $KeyId) } }
    if ($FromLabel -eq "") { $FromLabel = @($script:HordeDecisionRouteSettings.settings | Where-Object { $_.name -ceq "fromLabel" })[0].default }
    $now = (& $Clock).ToUniversalTime()
    if ($null -eq $Memory) { $Memory = @{} }
    # WHAT WAS SENT BEFORE IS ASKED FIRST (T-0391): whether the Orcs' own sessions took the notices already accepted.
    # Whatever the rest of the pass finds, its lines are said; the awaiting list is read before any messenger is looked for.
    $takenLines = @()
    $takenState = Read-HordeDecisionRouteTaken -HordeHome $HordeHome
    if ($takenState.state -cne "known" -or @($takenState.value.awaiting).Count -gt 0) {
        $takenMessenger = $null
        $takenFound = Find-HordeMessenger -Require $script:HordeDecisionRouteMessengerNeeds
        if ($takenFound.state -ceq "known") { $takenMessenger = $takenFound.value }
        $takenTick = Invoke-HordeDecisionRouteTakenTick -HordeHome $HordeHome -Messenger $takenMessenger -Now $now -AlarmSeconds $TakenAlarmSeconds -AfterAlarmSeconds $TakenAfterAlarmSeconds -TtlSeconds $script:HordeDecisionRouteTtlSeconds -Memory $Memory
        $takenLines = @($takenTick.lines)
    }
    $result = { param([string]$Outcome, $Lines, [int]$Routed, [int]$Pending) return [pscustomobject]@{ outcome = $Outcome; lines = @(@($takenLines) + @($Lines)); routed = $Routed; pending = $Pending } }
    $list = $null
    try { $list = Invoke-HordeDecision -Operation "list" -Request @{ state = "all"; messages = $true } -Root $StoreRoot -Now $now } catch { $list = New-HordeUnknown -Reason $_.Exception.Message }
    if ($list.state -cne "known" -or $list.value.outcome -cne "done") {
        return (& $result "pending" @("pending: the decisions list could not be read (" + $(if ($list.state -ceq "known") { $list.value.reason } else { $list.reason }) + "); nothing is lost, it is read again") 0 0)
    }
    $within = Get-HordeDecisionSetting -Name "decisions.answers.routeWithinHours"
    $work = @(Get-HordeDecisionRouteWork -List $list.value -Now $now -WithinHours $within)
    if ($work.Count -eq 0) { return (& $result "nothing" @() 0 0) }
    $found = Find-HordeMessenger -Require $script:HordeDecisionRouteMessengerNeeds
    if ($found.state -cne "known") {
        $why = $(if ($found.state -ceq "absent") { "no messenger on this machine can deliver to a session (" + $found.reason + ")" } else { "no messenger was chosen: " + $found.reason })
        return (& $result "pending" @("pending: " + $work.Count + " answer(s) to route wait: " + $why + ". Nothing is lost: they are tried again") 0 $work.Count)
    }
    $messenger = $found.value
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return (& $result "pending" @("pending: this machine's device id could not be had (" + $_.Exception.Message + "); the answers wait") 0 $work.Count) }
    $lines = New-Object System.Collections.ArrayList
    $routed = 0
    $pending = 0
    foreach ($item in $work) {
        $number = [int]$item.question.number
        $seq = [long]$item.answer.sequence
        $what = $(if ($item.purpose -ceq "nudge") { "the reminder for question " + $number } elseif ($item.purpose -ceq "closed") { "the closing notice of question " + $number } else { "answer record " + $seq + " of question " + $number })
        $target = Resolve-HordeDecisionRouteTarget -Question $item.question -Seat $Seat
        # AN ORC SEAT THAT CANNOT BE PROVEN JUST NOW is waited for, not given up: the route record is one
        # per answer and purpose, so an answer sent to the warchief for a seat that was only restarting
        # would never go to its Orc when the Orc is back. Only absent, or still unprovable after the grace,
        # falls back to the warchief.
        $graceKey = $item.purpose + "|" + $number + "|" + $seq
        if ($target.seatState -cne "unknown") { $script:HordeDecisionRouteUnknownSince.Remove($graceKey) }
        else {
            if (-not $script:HordeDecisionRouteUnknownSince.ContainsKey($graceKey)) { $script:HordeDecisionRouteUnknownSince[$graceKey] = $now }
            $waited = ($now - [datetime]$script:HordeDecisionRouteUnknownSince[$graceKey]).TotalSeconds
            if ($waited -lt $SeatGraceSeconds) {
                $pending++
                [void]$lines.Add("pending: " + $what + " waits for " + (Get-HordeDecisionAsker -AskedBy "$($item.question.askedBy)").shown + "'s seat, which cannot be proven just now (" + $target.seatWhy + "); waiting up to " + $SeatGraceSeconds + " s for that Orc's seat, then it goes to the warchief")
                continue
            }
        }
        if (-not $target.ok) { $pending++; [void]$lines.Add("pending: " + $what + " was not sent: " + $target.problem + ". It is tried again"); continue }
        $noticeId = Get-HordeDecisionRouteNoticeId -HordeHome $HordeHome -Purpose $item.purpose -Number $number -Answer $seq -SessionId $target.sessionId
        # The founder, verified, or only his label (header): asked as the notice is made, for this one answer.
        $signer = @([pscustomobject]@{ question = $number; message = "" + $seq; at = "$($item.answer.at)"; route = "$($item.answer.route)"; evidence = "$($item.answer.evidence)"; signedBy = "$($item.answer.signedBy)" })
        $who = Get-HordeDecisionNotifyVerified -Items $signer -Trust $Trust
        # THE CLOSING NOTICE IS HORDE'S OWN WORD, never the founder's: it vouches for nothing of his.
        if ($item.purpose -ceq "closed") { $who = [pscustomobject]@{ verified = $null; why = ""; claimed = $false } }
        # THE WORDING HE SAW (header): his signature vouches for words against the wording he answered; a
        # question reworded since is not vouched for, whatever the passkey says.
        $wording = Get-HordeDecisionRouteWording -Item $item
        if ($null -ne $who.verified -and $wording.differs) {
            $who = [pscustomobject]@{ verified = $null; why = ("the question was reworded after he answered (he answered wording " + $wording.answered + ", it is now wording " + $wording.now + ")"); claimed = $true }
        }
        # Verified: the founder, under the label wezfleet needs beside it. Otherwise: Horde itself, the
        # reserved system sender, which is the true name of the poster (header, WHO THE POSTER IS).
        $fromHere = $(if ($null -ne $who.verified) { [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeDecisionRouteFrom; label = $FromLabel; verified = $who.verified } } else { [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeDecisionRouteFrom; system = "horde" } })
        $message = [pscustomobject]@{ messageId = $noticeId; sessionId = $target.sessionId; from = $fromHere; body = (Format-HordeDecisionRouteNotice -Item $item -Target $target -HordeHome (Get-HordeDecisionRouteStoreHome -StoreRoot $StoreRoot -HordeHome $HordeHome)); ttlSeconds = $script:HordeDecisionRouteTtlSeconds }
        # THE MARK IS WRITTEN BEFORE THE POST (T-0391 slice 2). A list that cannot be read or written (corrupt, disk full, locked)
        # means nothing is posted: the answer stays pending and the reason is said (the same line every pass, which the turn
        # says once), instead of a post every pass that then fails to be listed. A crash between the mark and the post only
        # costs an alarm at takenAlarmSeconds; the next pass posts the same notice id, which wezfleet writes once and never
        # knocks for again (lib/MailPost.ps1 already-posted), and the mark keeps its first clock. A notice already TAKEN in
        # this process is not listed again (its route record failed; its post is a repost), so it is not reported TAKEN twice.
        if (-not $Memory.ContainsKey("delivered-" + $noticeId)) {
            $awaited = Add-HordeDecisionRouteTaken -HordeHome $HordeHome -NoticeId $noticeId -Answer $seq -SessionId "$($target.sessionId)" -Now $now
            foreach ($awaitedLine in @($awaited.lines)) { [void]$lines.Add($awaitedLine) }
            if (-not $awaited.ok) {
                $pending++
                [void]$lines.Add("pending: " + $what + " was not sent: it cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be, and the answer waits")
                continue
            }
        }
        $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
        if ($posted.state -cne "known" -or $script:HordeDecisionRouteStages -cnotcontains "$($posted.value.stage)") {
            $pending++
            $why = $(if ($posted.state -ceq "known") { "the messenger answered " + $posted.value.stage + $(if ($null -ne $posted.value.PSObject.Properties["reason"] -and "$($posted.value.reason)" -ne "") { ": " + $posted.value.reason } else { "" }) } else { "the messenger did not take it: " + $posted.reason })
            [void]$lines.Add("pending: " + $what + " was not sent (" + $why + "); nothing is recorded, and it is tried again")
            continue
        }
        $toldAnalyst = ""
        if ($item.purpose -ceq "answer") {
            $token = "[route " + $noticeId + "]"
            $sent = $null
            try { $sent = & $Analyst (Format-HordeDecisionRouteAnalystLine -Item $item -Target $target -Token $token) $token (ConvertFrom-HordeDecisionRouteTime -Text "$($item.answer.at)") } catch { $sent = [pscustomobject]@{ ok = $false; said = ("not left for the analyst: " + $_.Exception.Message) } }
            $toldAnalyst = $(if ($null -eq $sent) { "not left for the analyst: nothing answered" } else { "$($sent.said)" })
            $toldAnalyst = [regex]::Replace($toldAnalyst, '[\r\n]+', ' ').Trim()
            if ($toldAnalyst -eq "") { $toldAnalyst = "left for the analyst" }
        }
        $request = [ordered]@{ id = (Get-HordeDecisionRouteRecordId -Purpose $item.purpose -Number $number -Answer $seq); actor = "warchief"; number = $number; answer = $seq; purpose = $item.purpose; seat = $target.seat; label = $target.label; sessionId = $target.sessionId; resolved = [bool]$target.resolved; notice = $noticeId }
        if ($target.note -ne "") { $request["note"] = $target.note }
        if ($toldAnalyst -ne "") { $request["analyst"] = $toldAnalyst }
        $wrote = Invoke-HordeDecision -Operation "route" -Request $request -Root $StoreRoot -Now $now
        $to = $(if ($target.seat -ceq "orc") { "Orc " + $target.label } else { "the warchief" })
        $wake = Format-HordeMessengerWake -Answer $posted
        $how = "through messenger " + $messenger.name + " (" + $posted.value.stage + $(if ($wake -cne "") { "; " + $wake } else { "" }) + ")"
        if ($null -ne $who.verified) { $how = $how + ", as the founder, verified by his passkey " + $who.verified.keyId }
        elseif ($who.claimed) { $how = $how + ", not verified: " + $who.why }
        if ($wrote.state -ceq "known" -and @("done", "replayed") -ccontains "$($wrote.value.outcome)") {
            $routed++
            $verb = $(if ($item.purpose -ceq "nudge") { "reminded " + $to + " of question " + $number + " (answer record " + $seq + ", still open)" } elseif ($item.purpose -ceq "closed") { "told " + $to + " that the warchief closed question " + $number } else { "routed " + $what + " to " + $to })
            [void]$lines.Add($verb + ", " + $how + $(if ($target.note -ne "") { "; " + $target.note } else { "" }) + "; SENT, not yet delivered: awaiting the session's own TAKEN")
            continue
        }
        # THE NOTICE WAS TAKEN AND ITS RECORD WAS NOT WRITTEN: the next pass sends the same notice under
        # the same id, which the messenger keeps as one, and writes the record then.
        $pending++
        $why = $(if ($wrote.state -ceq "known") { $wrote.value.reason } else { $wrote.reason })
        [void]$lines.Add("pending: " + $what + " was sent to " + $to + " " + $how + ", but its record could not be written (" + $why + "); the next pass sends the same notice, which the messenger keeps as one")
    }
    return (& $result $(if ($pending -gt 0) { "pending" } else { "routed" }) @($lines) $routed $pending)
}

function Get-HordeDecisionRouteMutexName {
    # The one router of -HordeHome, in the namespace every session of this machine shares (as the bell's).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant())) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return ("Global\horde-" + $script:HordeDecisionRouteModule + "-" + $hash.Substring(0, 16))
}

function Get-HordeDecisionRouteStoreMark {
    # A cheap look at whether the store changed: how many files, and the last name. Only a hint.
    param([string]$Root = "")
    try {
        $folder = $Root
        if ($folder -eq "") { $folder = Get-HordeDecisionStoreRoot }
        if (-not [System.IO.Directory]::Exists($folder)) { return "none" }
        $names = [System.IO.Directory]::GetFiles($folder)
        $newest = ""
        foreach ($n in $names) { if ([string]::CompareOrdinal($n, $newest) -gt 0) { $newest = $n } }
        return ("" + $names.Length + "|" + $newest)
    } catch { return "unknown" }
}

function Invoke-HordeDecisionRouteTurn {
    # ONE TURN, for a caller that turns it again and again (the relay runner's decisions channel) or once
    # (`horde decisions route`, with -Force). -Memory is the caller's own table, kept between turns. A
    # pass is run when the store changed, the setting passSeconds has passed, or -Force; and only while
    # this turn holds the home's router mutex - another holder means outcome elsewhere, and nothing is
    # done. Returns { outcome; lines; againMs }: lines only those not said by the turn before, so a pending
    # line is said once and not every tick.
    param([Parameter(Mandatory = $true)][hashtable]$Memory, [string]$HordeHome = "", [string]$StoreRoot = "", [switch]$Force, [scriptblock]$Clock = $null, [scriptblock]$Seat = $null, [scriptblock]$Analyst = $null, [scriptblock]$Trust = $null)
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    $settings = Get-HordeDecisionRouteSettings -HordeHome $HordeHome
    if ($settings.state -ceq "refused") {
        $line = "answers are not routed, because the route settings file is refused: " + (@($settings.findings) -join "; ")
        $new = @(); if ($line -cne "$($Memory['said'])") { $new = @($line) }; $Memory["said"] = $line
        return [pscustomobject]@{ outcome = "refused"; lines = $new; againMs = 0 }
    }
    $v = $settings.values
    $now = & $Clock
    $mark = Get-HordeDecisionRouteStoreMark -Root $StoreRoot
    $due = $Force -or (-not $Memory.ContainsKey("mark")) -or $mark -cne "$($Memory['mark'])" -or ($now - [datetime]$Memory["passAt"]).TotalSeconds -ge [int]$v.passSeconds
    if (-not $due) { return [pscustomobject]@{ outcome = "idle"; lines = @(); againMs = 0 } }
    $mutex = $null
    try { $mutex = New-Object System.Threading.Mutex($false, (Get-HordeDecisionRouteMutexName -HordeHome $HordeHome)) } catch { return [pscustomobject]@{ outcome = "elsewhere"; lines = @(); againMs = 0 } }
    $mine = $false
    try { $mine = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mine = $true }
    if (-not $mine) { $mutex.Dispose(); return [pscustomobject]@{ outcome = "elsewhere"; lines = @(); againMs = 0 } }
    $pass = $null
    if (-not $Memory.ContainsKey("taken")) { $Memory["taken"] = @{} }
    try { $pass = Invoke-HordeDecisionRoutePass -Clock $Clock -Seat $Seat -Analyst $Analyst -HordeHome $HordeHome -StoreRoot $StoreRoot -FromLabel "$($v.fromLabel)" -SeatGraceSeconds ([int]$v.seatGraceSeconds) -Trust $Trust -TakenAlarmSeconds ([int]$v.takenAlarmSeconds) -TakenAfterAlarmSeconds ([int]$v.takenAfterAlarmSeconds) -Memory $Memory["taken"] }
    finally { try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose() }
    # The mark AFTER the pass: the records this pass wrote itself are no change to read again for. A record
    # another writer made during the pass is read at the latest passSeconds later.
    $Memory["mark"] = Get-HordeDecisionRouteStoreMark -Root $StoreRoot
    $Memory["passAt"] = $now
    $said = @($pass.lines)
    $text = $said -join "`n"
    $new = @()
    if ($text -cne "$($Memory['said'])") { $new = $said }
    $Memory["said"] = $text
    # A pass that left something pending turns again after passSeconds, as every pass does; a test or a
    # person who wants it sooner runs `horde decisions route`.
    return [pscustomobject]@{ outcome = $pass.outcome; lines = $new; againMs = 0 }
}
