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
# on; it says that the list is the authority and that it authorizes nothing. It names no passkey, claims
# no verified sender and touches no check of a question that needs a passkey.
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
    @{ name = "fromLabel"; kind = "label"; default = "F"; what = "The hub label a routed answer is from: the founder's, F, whose words it carries." }
)
# Who the notice is from: the router is no session, so it names itself, as the bell does.
$script:HordeDecisionRouteFrom = "horde-decisions-route"
# How long a notice may wait in a mailbox: the link's most, 7 days, as the bell's.
$script:HordeDecisionRouteTtlSeconds = 604800
$script:HordeDecisionRouteStages = @("accepted", "handed-over", "seen")
# The most of his words, and of a title, the analyst's one line carries.
$script:HordeDecisionRouteAnalystChars = 300

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

function Resolve-HordeDecisionRouteTarget {
    # Where one answer goes (header, WHERE IT GOES): { ok; seat; label; sessionId; resolved; note; problem }.
    # ok $false, with the problem, only when even the warchief's seat cannot be had. -Seat answers, for a
    # role and a label ("" for a seat by role alone), a core/Tristate.ps1 answer whose known value has
    # sessionId: core/SessionSeat.ps1's two readers, or a test's stand-in.
    param([Parameter(Mandatory = $true)]$Question, [Parameter(Mandatory = $true)][scriptblock]$Seat)
    $asker = Get-HordeDecisionAsker -AskedBy "$($Question.askedBy)"
    $note = ""
    if ($asker.seat -ceq "orc") {
        $found = $null
        try { $found = & $Seat "orc" $asker.label } catch { $found = New-HordeUnknown -Reason $_.Exception.Message }
        if ($null -ne $found -and "$($found.state)" -ceq "known" -and "$($found.value.sessionId)" -ne "") {
            return [pscustomobject]@{ ok = $true; seat = "orc"; label = $asker.label; sessionId = "$($found.value.sessionId)"; resolved = $true; note = ""; problem = "" }
        }
        $why = $(if ($null -eq $found) { "nothing answered" } elseif ("$($found.reason)" -ne "") { "$($found.reason)" } else { "no live session wears its label with the role orc" })
        $note = $asker.shown + "'s seat could not be found (" + $why + "), so the answer went to the warchief instead"
    }
    elseif ($asker.seat -cne "warchief") { $note = $asker.why + "; it went to the warchief instead" }
    $boss = $null
    try { $boss = & $Seat "warchief" "" } catch { $boss = New-HordeUnknown -Reason $_.Exception.Message }
    if ($null -eq $boss -or "$($boss.state)" -cne "known" -or "$($boss.value.sessionId)" -eq "") {
        $why = $(if ($null -eq $boss) { "nothing answered" } elseif ("$($boss.reason)" -ne "") { "$($boss.reason)" } else { "no live session holds the role" })
        $lead = $(if ($note -ne "") { $note + ", and " } else { "" })
        return [pscustomobject]@{ ok = $false; seat = ""; label = ""; sessionId = ""; resolved = $false; note = $note; problem = ($lead + "the warchief's seat cannot be had: " + $why) }
    }
    return [pscustomobject]@{ ok = $true; seat = "warchief"; label = ""; sessionId = "$($boss.value.sessionId)"; resolved = ($note -eq ""); note = $note; problem = "" }
}

function Format-HordeDecisionRouteNotice {
    # The notice's body: plain lines, the question's number and title, who answered and by what route,
    # his words whole, what to do, and that it authorizes nothing (header, ROUTING IS NOT AUTHORIZING).
    param([Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)]$Target)
    $q = $Item.question
    $m = $Item.answer
    $number = [int]$q.number
    $seq = [long]$m.sequence
    $lines = New-Object System.Collections.ArrayList
    $part = $(if ("$($m.part)" -ne "") { " (part " + $m.part + ")" } else { "" })
    $mine = ($Target.seat -ceq "orc")
    if ($Item.purpose -ceq "nudge") {
        [void]$lines.Add("UNCLOSED QUESTION " + $number + ": " + $Item.flag + ". This is the one reminder for this answer.")
    }
    elseif ($mine -or ($Target.resolved -and $Target.seat -ceq "warchief")) {
        [void]$lines.Add("FOUNDER ANSWER to your question " + $number + $part + ", routed to you by Horde.")
    }
    else {
        [void]$lines.Add("FOUNDER ANSWER to question " + $number + $part + ", asked by '" + $q.askedBy + "', sent to you, the warchief: " + $Target.note + ".")
    }
    [void]$lines.Add("Question " + $number + ": " + $q.title)
    [void]$lines.Add("Answered by the founder, " + "$($m.routeShown)" + " (record " + $seq + ", " + $m.at + ").")
    if ($Item.purpose -ceq "answer") {
        [void]$lines.Add("His words:")
        foreach ($l in @(([string]$m.text) -split "\r?\n")) { [void]$lines.Add("  " + $l) }
    }
    if ($mine) {
        [void]$lines.Add("When you have taken it, acknowledge it. That closes the question, with you as the closer:")
        [void]$lines.Add("  horde decisions ack " + $number + " -Answer " + $seq)
    }
    else {
        [void]$lines.Add("When it is dealt with, close it: horde decisions close " + $number + " -Outcome <one line>")
    }
    [void]$lines.Add("The list is the authority (horde decisions show " + $number + "). This copy authorizes nothing: a question that needs a passkey is authorized only by its own check.")
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
    $cut = { param([string]$Text) $first = @(([string]$Text) -split "\r?\n")[0]; if ($first.Length -gt $script:HordeDecisionRouteAnalystChars) { $first = $first.Substring(0, $script:HordeDecisionRouteAnalystChars) + "..." }; return $first }
    $to = $(if ($Target.seat -ceq "orc") { "Orc " + $Target.label } else { "the warchief" + $(if (-not $Target.resolved) { " (askedBy '" + $Item.question.askedBy + "' could not be resolved)" } else { "" }) })
    return ("DECISION: question " + $Item.question.number + " (" + (& $cut "$($Item.question.title)") + ") answered by the founder, " + $Item.answer.routeShown + " (record " + $Item.answer.sequence + "): " + (& $cut ([string]$Item.answer.text)) + " - sent to " + $to + ". " + $Token)
}

function Invoke-HordeDecisionRoutePass {
    # ONE PASS (header): read the list, send what is due, record each send. Returns { outcome; lines;
    # routed; pending }: outcome nothing, routed or pending; lines one plain line for each answer sent,
    # reminded or left pending; routed and pending how many. -Clock, -Seat and -Analyst are for a test
    # that hands in its own; -StoreRoot names a store that is not this home's own.
    param([scriptblock]$Clock = $null, [scriptblock]$Seat = $null, [scriptblock]$Analyst = $null, [string]$HordeHome = "", [string]$StoreRoot = "", [string]$FromLabel = "")
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Seat) { $Seat = { param([string]$Role, [string]$Label) if ($Label -ceq "") { return (Get-HordeRoleSeat -Role $Role) }; return (Get-HordeLabelSeat -Label $Label -Role $Role) } }
    if ($null -eq $Analyst) { $Analyst = { param([string]$Text, [string]$Token, $Since) return (Send-HordeDecisionRouteAnalyst -Text $Text -Token $Token -HordeHome $HordeHome -Since $Since) } }
    if ($FromLabel -eq "") { $FromLabel = @($script:HordeDecisionRouteSettings.settings | Where-Object { $_.name -ceq "fromLabel" })[0].default }
    $result = { param([string]$Outcome, $Lines, [int]$Routed, [int]$Pending) return [pscustomobject]@{ outcome = $Outcome; lines = @($Lines); routed = $Routed; pending = $Pending } }
    $now = (& $Clock).ToUniversalTime()
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
    $from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeDecisionRouteFrom; label = $FromLabel }
    $lines = New-Object System.Collections.ArrayList
    $routed = 0
    $pending = 0
    foreach ($item in $work) {
        $number = [int]$item.question.number
        $seq = [long]$item.answer.sequence
        $what = $(if ($item.purpose -ceq "nudge") { "the reminder for question " + $number } else { "answer record " + $seq + " of question " + $number })
        $target = Resolve-HordeDecisionRouteTarget -Question $item.question -Seat $Seat
        if (-not $target.ok) { $pending++; [void]$lines.Add("pending: " + $what + " was not sent: " + $target.problem + ". It is tried again"); continue }
        $noticeId = Get-HordeDecisionRouteNoticeId -HordeHome $HordeHome -Purpose $item.purpose -Number $number -Answer $seq -SessionId $target.sessionId
        $message = [pscustomobject]@{ messageId = $noticeId; sessionId = $target.sessionId; from = $from; body = (Format-HordeDecisionRouteNotice -Item $item -Target $target); ttlSeconds = $script:HordeDecisionRouteTtlSeconds }
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
        if ($wrote.state -ceq "known" -and @("done", "replayed") -ccontains "$($wrote.value.outcome)") {
            $routed++
            $verb = $(if ($item.purpose -ceq "nudge") { "reminded " + $to + " of question " + $number + " (answer record " + $seq + ", still open)" } else { "routed " + $what + " to " + $to })
            [void]$lines.Add($verb + ", " + $how + $(if ($target.note -ne "") { "; " + $target.note } else { "" }))
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
    param([Parameter(Mandatory = $true)][hashtable]$Memory, [string]$HordeHome = "", [string]$StoreRoot = "", [switch]$Force, [scriptblock]$Clock = $null, [scriptblock]$Seat = $null, [scriptblock]$Analyst = $null)
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
    try { $pass = Invoke-HordeDecisionRoutePass -Clock $Clock -Seat $Seat -Analyst $Analyst -HordeHome $HordeHome -StoreRoot $StoreRoot -FromLabel "$($v.fromLabel)" }
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
