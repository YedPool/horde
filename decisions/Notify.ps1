# decisions/Notify.ps1 - `horde decisions notify`: tells the warchief's session that the founder has
# answered in the decisions window, through a messenger, naming question numbers only.
#
# WHAT IT DOES. It watches the store, and once the founder has said something the warchief has not read
# and no new answer has come for the quiet period (the setting quietSeconds, 30 s), it sends ONE notice
# for that set. The notice holds the count and the question numbers, the one command that prints his
# words (horde decisions inbox), and nothing of what he said: the store is the authority, and a notice
# that quoted him would be a second copy of his words that nobody marks read. It was a trial watcher
# outside the repository first (2026-10-07); every behaviour below is one that trial measured.
#
# THE QUIET RULE (Get-HordeDecisionNotifyDue). A set rings when the newest answer in it is quietSeconds
# old AND the reading it rings on BEGAN after that moment. Measured in the trial on 2026-10-07: a
# reading begun 3 s before the deadline missed an answer stored 2 s before it, and the set rang as two.
# An answer's time is the store's own, unless that is in the future; then it is when notify first saw it.
#
# THE SEND GOES THROUGH THE MESSENGER PORT ONLY (messengers/Port.ps1). This file names no messenger: it
# states, in ONE list ($script:HordeDecisionNotifyMessengerNeeds), what a messenger must offer, and the
# port answers with the one loaded messenger that offers it (Find-HordeMessenger). A messenger that lands
# later is picked with no change here. The list, and why each is on it:
#   body.untyped     the notice must never be typed into the warchief's input box: typed text is the
#                    defect family the fleet's mail was built to end.
#   idempotent.post  the notice's id is made from the set (Get-HordeDecisionNotifyMessageId), and a
#                    retry - after a crash between the post and the record, or after an answer that
#                    could not say - must be the same one message, never a second.
#   wake             a doorbell that leaves an idle session asleep rings for nobody. This is also what
#                    keeps the in-process test messenger out: it offers no wake.
# NOT receipt.receiver: "told" means the messenger took the notice into the session's mailbox (stage
# accepted or later). Whether he read the answers is the store's own read mark (inbox and mark-read),
# not the messenger's receipt.
# NOTHING IS CLAIMED THAT DID NOT HAPPEN. No messenger, two of them (one is never chosen), no warchief's
# seat, a post the messenger did not accept: the set stays PENDING, the line says why in plain words,
# nothing is recorded, and it is tried again after a back-off (30 s, doubling, at most 5 min). Nothing
# is lost: the answers stay unread in the store, and the next try, or the next start, finds them.
#
# THE TOLD RECORD, <HordeHome>\decisions\notify-told.json, never inside the store:
#   { "schemaVersion": 1, "rung": [ { "question": 14, "message": "57", "at": "<UTC>", "notice": "<uuid>" } ] }
# message is the record's sequence number as text. An entry is added ONLY after the messenger accepted
# the notice. It is written to a temporary file and moved over the old one in one step
# (core/FileAtomic.ps1), so a reader sees the old record or the new one. THIS FILE IS THE ONE PLACE THAT
# WRITES IT AND THE ONE THAT READS IT: the window reads it through Read-HordeDecisionNotifyRecord to
# mark a message "told". A RECORD THAT EXISTS AND CANNOT BE READ REFUSES: notify rings nothing and says
# so, because ringing from an empty memory would ring again for everything ever told; the file is left
# as it is for a person to mend or move.
# A crash between the post and the record leaves the set untold; the next pass posts the same notice
# with the same id, and the messenger (idempotent.post) keeps it as one.
#
# ONE PER HOME: a named mutex (Local\, ending in a fingerprint of the home). A second notify for the
# same home says so and leaves. ASKED TO STOP (the window closed), it does not drop an answer still in
# its quiet period: it stays until that period ends and rings, for at most $script:HordeDecisionNotifyLingerSeconds,
# then leaves; what is still untold rings at the next start.
#
# `horde decisions open` starts it beside the window when the setting startWithWindow says so (true),
# in a PowerShell of its own inside the window's process (Start-HordeDecisionNotifyBeside), and stops it
# when the window closes: no program is started for it.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Operations.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\SessionSeat.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Device.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "messengers\Port.ps1")
# Every messenger, at script level, as a messenger must be loaded; one already registered in this
# session (this file loaded twice) is not loaded again, because a second registration is refused.
foreach ($notifyMessengerFile in @(Get-HordeMessengerFiles)) {
    if (@(Get-HordeMessengerNames) -cnotcontains (Split-Path -Leaf (Split-Path -Parent $notifyMessengerFile))) { . $notifyMessengerFile }
}

# THE ONE LIST of what a messenger must offer to carry the notice (header, and why each).
$script:HordeDecisionNotifyMessengerNeeds = @("body.untyped", "idempotent.post", "wake")
$script:HordeDecisionNotifyModule = "decisions-notify"
$script:HordeDecisionNotifySettings = New-HordeModuleSettings -Module $script:HordeDecisionNotifyModule -Settings @(
    @{ name = "quietSeconds"; kind = "whole"; default = 30; min = 0; max = 3600; what = "How long after the newest answer, with no other, the notice for the set is sent, in seconds." }
    @{ name = "pollSeconds"; kind = "whole"; default = 3; min = 1; max = 600; what = "How often the store's folder is looked at for a change, in seconds." }
    @{ name = "rereadSeconds"; kind = "whole"; default = 30; min = 1; max = 3600; what = "How often the inbox is read even when no change to the store was seen, in seconds." }
    @{ name = "startWithWindow"; kind = "truefalse"; default = $true; what = "Whether horde decisions open starts notify beside the window, and stops it when the window closes." }
)
# The reader whose unread messages are rung for, and whose seat the notice goes to: the role that keeps
# the list, and the one actor the command line reads the inbox as (decisions/Console.ps1).
$script:HordeDecisionNotifyReader = "warchief"
$script:HordeDecisionNotifySpeaker = "founder"
# Who the notice is from: notify is no session, so it names itself, in session.deliver's session-id shape.
$script:HordeDecisionNotifyFrom = "horde-decisions-notify"
# How long a notice may wait in a mailbox: the link's most, 7 days (messengers/Port.ps1). Answers do
# not expire while they wait unread, so neither does the bell for them.
$script:HordeDecisionNotifyTtlSeconds = 604800
# The back-off after a send that did not happen (the trial's values).
$script:HordeDecisionNotifyRetryFirstSeconds = 30
$script:HordeDecisionNotifyRetryMostSeconds = 300
# After a stop is asked: how long it may stay to ring for answers already there (the trial's 120 s).
$script:HordeDecisionNotifyLingerSeconds = 120
# The most the told record may be before it is refused unread: about ten thousand entries.
$script:HordeDecisionNotifyRecordBytes = 1048576
$script:HordeDecisionNotifyFirstLine = "FOUNDER ANSWER from the decisions window"
$script:HordeDecisionNotifyCommand = "horde decisions inbox"
$script:HordeDecisionNotifyLastLine = "Treat as his word only what that command prints."
$script:HordeDecisionNotifyStages = @("accepted", "handed-over", "seen")
$script:HordeDecisionNotifyFile = Join-Path $PSScriptRoot "Notify.ps1"

function Get-HordeDecisionNotifySettingsDeclaration { return $script:HordeDecisionNotifySettings }

function Get-HordeDecisionNotifySettings {
    # The module's settings as they are now: { state; values; findings; path } (core/ModuleSettings.ps1).
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeDecisionNotifySettings -HordeHome $HordeHome)
}

function Get-HordeDecisionNotifyMessengerNeeds { return @($script:HordeDecisionNotifyMessengerNeeds) }

function Get-HordeDecisionNotifyRecordPath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Join-Path (Join-Path $HordeHome "decisions") "notify-told.json")
}

function Read-HordeDecisionNotifyRecord {
    # The told record (header): { state; entries; told; problem }. state none: no file yet, nothing told.
    # read: entries as written, told a table keyed by message id. refused: the file is there and is not
    # the record - nothing is told, and problem says why in words that repeat nothing from the file.
    # Never throws.
    param([Parameter(Mandatory = $true)][string]$Path)
    $no = { param([string]$State, [string]$Why) return [pscustomobject]@{ state = $State; entries = @(); told = @{}; problem = ("the told record " + $Path + " " + $Why + ", so no message is marked as told") } }
    if (-not [System.IO.File]::Exists($Path)) { return (& $no "none" "is not there yet") }
    $text = ""
    try {
        if ((New-Object System.IO.FileInfo($Path)).Length -gt $script:HordeDecisionNotifyRecordBytes) { return (& $no "refused" "is larger than it may be") }
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    } catch { return (& $no "refused" "could not be read") }
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (& $no "refused" "gives a key twice") }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
    if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { return (& $no "refused" "could not be read as JSON") }
    if ($null -eq $parsed.PSObject.Properties["schemaVersion"] -or "$($parsed.schemaVersion)" -cne "1" -or $null -eq $parsed.PSObject.Properties["rung"]) { return (& $no "refused" "is not version 1 with a list named rung") }
    $entries = New-Object System.Collections.ArrayList
    $told = @{}
    foreach ($e in @($parsed.rung)) {
        if ($null -eq $e) { continue }
        $ok = ($e -is [System.Management.Automation.PSCustomObject] -and $null -ne $e.PSObject.Properties["message"] -and $null -ne $e.PSObject.Properties["question"])
        if ($ok) { $ok = ("$($e.message)" -cmatch '\A[1-9][0-9]{0,17}\z' -and "$($e.question)" -cmatch '\A[1-9][0-9]{0,8}\z') }
        if (-not $ok) { return (& $no "refused" "holds an entry whose message is not a record number or whose question is not a question number") }
        $notice = ""; if ($null -ne $e.PSObject.Properties["notice"]) { $notice = "$($e.notice)" }
        $at = ""; if ($null -ne $e.PSObject.Properties["at"]) { $at = "$($e.at)" }
        [void]$entries.Add([pscustomobject]@{ question = [int]"$($e.question)"; message = "$($e.message)"; at = $at; notice = $notice })
        $told["$($e.message)"] = $true
    }
    return [pscustomobject]@{ state = "read"; entries = @($entries); told = $told; problem = "" }
}

function Write-HordeDecisionNotifyRecord {
    # The told record, whole (header): written beside itself, then moved over the old one in one step.
    param([Parameter(Mandatory = $true)][string]$Path, [object[]]$Entries = @())
    $folder = Split-Path -Parent $Path
    if (-not [System.IO.Directory]::Exists($folder)) { [void][System.IO.Directory]::CreateDirectory($folder) }
    $rung = @($Entries | ForEach-Object { [ordered]@{ question = [int]$_.question; message = "$($_.message)"; at = "$($_.at)"; notice = "$($_.notice)" } })
    # Written by hand around ConvertTo-Json: 5.1 writes a one-element list inside an object as the element.
    $parts = @($rung | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress })
    $text = '{"schemaVersion":1,"rung":[' + ($parts -join ",") + ']}' + "`r`n"
    if ($text -cnotmatch '\A[\x20-\x7E\r\n]+\z') { throw "the told record would not be plain ASCII, and is not written" }
    $temp = $Path + "." + $PID + ".tmp"
    [System.IO.File]::WriteAllText($temp, $text, (New-Object System.Text.UTF8Encoding($false)))
    Move-HordeFileAtomic -From $temp -To $Path
}

function ConvertFrom-HordeDecisionNotifyTime {
    # A stored time as UTC, or $null when it is not one.
    param([string]$Text)
    $stamp = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$stamp)) { return $stamp }
    return $null
}

function Get-HordeDecisionNotifyArrival {
    # When one message arrived (header, THE QUIET RULE): the store's time unless it is in the future,
    # then when notify first saw it.
    param([Parameter(Mandatory = $true)]$Item, [System.Collections.IDictionary]$FirstSeen, [datetime]$Now)
    $stored = ConvertFrom-HordeDecisionNotifyTime -Text "$($Item.at)"
    if ($null -ne $stored -and $stored -le $Now) { return $stored }
    if ($null -ne $FirstSeen -and $FirstSeen.Contains("$($Item.message)")) { return [datetime]$FirstSeen["$($Item.message)"] }
    return $Now
}

function Get-HordeDecisionNotifyDue {
    # PURE. Is the set -Pending due now? { due; reread; wakeAt; newest }. due: quiet has passed, the
    # reading began after it did, and no back-off holds it. reread: quiet has passed but the reading
    # began before, so read again first. wakeAt: when to look again ($null with nothing pending).
    param([object[]]$Pending = @(), [System.Collections.IDictionary]$FirstSeen = @{}, [datetime]$Now, [int]$QuietSeconds, [datetime]$ReadStartedAt, [datetime]$NextAttemptAt = [datetime]::MinValue)
    $items = @($Pending | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return [pscustomobject]@{ due = $false; reread = $false; wakeAt = $null; newest = $null } }
    $newest = [datetime]::MinValue
    foreach ($i in $items) { $a = Get-HordeDecisionNotifyArrival -Item $i -FirstSeen $FirstSeen -Now $Now; if ($a -gt $newest) { $newest = $a } }
    $quietEnds = $newest.AddSeconds($QuietSeconds)
    if ($Now -lt $quietEnds) { return [pscustomobject]@{ due = $false; reread = $false; wakeAt = $quietEnds; newest = $newest } }
    if ($Now -lt $NextAttemptAt) { return [pscustomobject]@{ due = $false; reread = $false; wakeAt = $NextAttemptAt; newest = $newest } }
    if ($ReadStartedAt -lt $quietEnds) { return [pscustomobject]@{ due = $false; reread = $true; wakeAt = $Now; newest = $newest } }
    return [pscustomobject]@{ due = $true; reread = $false; wakeAt = $null; newest = $newest }
}

function Format-HordeDecisionNotifyCount {
    # "1 answer, on question 4" or "4 answers, on questions 3, 5 and 7": each number once, in order.
    param([object[]]$Items = @(), [string]$On = "on")
    $count = @($Items).Count
    $n = @($Items | ForEach-Object { [int]$_.question } | Sort-Object -Unique)
    $numbers = "question " + $n[0]
    if ($n.Count -gt 1) { $numbers = "questions " + (($n[0..($n.Count - 2)]) -join ", ") + " and " + $n[$n.Count - 1] }
    return ("" + $count + $(if ($count -eq 1) { " answer, " } else { " answers, " }) + $On + " " + $numbers)
}

function Format-HordeDecisionNotifyNotice {
    # The notice's body (header): the agreed first line, the count and the numbers, the command that
    # prints his words, and the closing sentence. Built from numbers alone: no text of a message is
    # handed to this function, so none can reach the notice.
    param([Parameter(Mandatory = $true)][object[]]$Items)
    return (@(
        $script:HordeDecisionNotifyFirstLine,
        ((Format-HordeDecisionNotifyCount -Items $Items -On "for") + "."),
        "Run this one command to read them (it prints his words, then marks them read):",
        $script:HordeDecisionNotifyCommand,
        $script:HordeDecisionNotifyLastLine
    ) -join "`r`n")
}

function Get-HordeDecisionNotifyMessageId {
    # The notice's id, made from the set (header, idempotent.post): the home and the messages' record
    # numbers, in any order, hashed and written as a lowercase uuid.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string[]]$Ids)
    $key = "horde-decisions-notify`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant() + "`n" + ((@($Ids | Sort-Object { [long]$_ }) | ForEach-Object { "$_" }) -join ",")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hex = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return ($hex.Substring(0, 8) + "-" + $hex.Substring(8, 4) + "-" + $hex.Substring(12, 4) + "-" + $hex.Substring(16, 4) + "-" + $hex.Substring(20, 12))
}

function Get-HordeDecisionNotifyUnread {
    # The founder's messages the warchief has not read, from an inbox answer: { ok; reason; items },
    # each item { question; message; at }. The inbox only reads (decisions/Operations.ps1).
    param($Answer)
    if ($null -eq $Answer -or "$($Answer.state)" -cne "known") { return [pscustomobject]@{ ok = $false; reason = $(if ($null -ne $Answer) { "$($Answer.reason)" } else { "no answer" }); items = @() } }
    if ("$($Answer.value.outcome)" -cne "done") { return [pscustomobject]@{ ok = $false; reason = "$($Answer.value.reason)"; items = @() } }
    $items = @($Answer.value.messages | Where-Object { $null -ne $_ -and "$($_.message.speaker)" -ceq $script:HordeDecisionNotifySpeaker } | ForEach-Object { [pscustomobject]@{ question = [int]$_.number; message = "" + [long]$_.message.sequence; at = "$($_.message.at)" } })
    return [pscustomobject]@{ ok = $true; reason = ""; items = $items }
}

function New-HordeDecisionNotifyTracker {
    # What one running notify keeps in memory: when it first saw each message, and the back-off.
    param([int]$QuietSeconds = 30)
    return [pscustomobject]@{ quietSeconds = $QuietSeconds; firstSeen = @{}; nextAttemptAt = [datetime]::MinValue; retryDelay = $script:HordeDecisionNotifyRetryFirstSeconds; problem = "" }
}

function Get-HordeDecisionNotifyName {
    # The name of the one notify of -HordeHome: fixed words and a fingerprint of the home's path.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant())) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return ("horde-" + $script:HordeDecisionNotifyModule + "-" + $hash.Substring(0, 16))
}

function Get-HordeDecisionNotifyStoreMark {
    # A cheap look at whether the store changed, so the inbox is not read every few seconds: how many
    # files, and the last name. Only a hint; the inbox is read every rereadSeconds whatever it says.
    try {
        $folder = Get-HordeDecisionStoreRoot
        if (-not [System.IO.Directory]::Exists($folder)) { return "none" }
        $names = [System.IO.Directory]::GetFiles($folder)
        $newest = ""
        foreach ($n in $names) { if ([string]::CompareOrdinal($n, $newest) -gt 0) { $newest = $n } }
        return ("" + $names.Length + "|" + $newest)
    } catch { return "unknown" }
}

function Format-HordeDecisionNotifyPending {
    # The line for a set that was not sent: the reason first, then that nothing is lost and when it is tried again.
    param([string]$Problem, [string]$What, [int]$Count, [datetime]$At)
    return ("pending: " + $Problem + ". " + $What + $(if ($Count -eq 1) { ", stays" } else { ", stay" }) + " untold, and nothing is lost: the next try is from " + $At.ToString("HH:mm:ss") + "Z.")
}

function Invoke-HordeDecisionNotifyPass {
    # ONE PASS: read the told record and the inbox, and ring for the set if it is due. Returns
    # { outcome; said; wakeAt; pending }: outcome nothing, waiting, reread, rang, pending or refused;
    # said the one plain line for it; wakeAt when to pass again ($null: no reason to); pending how many
    # answers wait untold. -Clock, -Inbox and -Seat are for a test that hands in its own.
    param([Parameter(Mandatory = $true)]$Tracker, [scriptblock]$Clock = $null, [scriptblock]$Inbox = $null, [scriptblock]$Seat = $null, [string]$HordeHome = "")
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    if ($null -eq $Inbox) { $Inbox = { return (Invoke-HordeDecision -Operation "inbox" -Request @{ actor = $script:HordeDecisionNotifyReader }) } }
    if ($null -eq $Seat) { $Seat = { return (Get-HordeRoleSeat -Role $script:HordeDecisionNotifyReader) } }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    $result = { param([string]$Outcome, [string]$Said, $WakeAt, [int]$Pending) return [pscustomobject]@{ outcome = $Outcome; said = $Said; wakeAt = $WakeAt; pending = $Pending } }
    $path = Get-HordeDecisionNotifyRecordPath -HordeHome $HordeHome
    $record = Read-HordeDecisionNotifyRecord -Path $path
    if ($record.state -ceq "refused") { return (& $result "refused" ("refused: " + $record.problem + ". Nothing is rung from an empty memory: mend or move the file, then start notify again.") $null 0) }
    $readStartedAt = & $Clock
    $unread = $null
    try { $unread = Get-HordeDecisionNotifyUnread -Answer (& $Inbox) } catch { $unread = [pscustomobject]@{ ok = $false; reason = $_.Exception.Message; items = @() } }
    $now = & $Clock
    if (-not $unread.ok) { return (& $result "pending" ("pending: the inbox could not be read (" + $unread.reason + "); it is read again shortly. Nothing is lost.") $null 0) }
    $pending = @($unread.items | Where-Object { -not $record.told.Contains($_.message) })
    foreach ($k in @($Tracker.firstSeen.Keys)) { if (@($pending | Where-Object { $_.message -ceq $k }).Count -eq 0) { $Tracker.firstSeen.Remove($k) } }
    foreach ($i in $pending) { if (-not $Tracker.firstSeen.Contains($i.message)) { $Tracker.firstSeen[$i.message] = $now } }
    if ($pending.Count -eq 0) { $Tracker.problem = ""; return (& $result "nothing" "nothing to ring for: no answer from the founder waits unread and untold" $null 0) }
    $what = Format-HordeDecisionNotifyCount -Items $pending
    $due = Get-HordeDecisionNotifyDue -Pending $pending -FirstSeen $Tracker.firstSeen -Now $now -QuietSeconds $Tracker.quietSeconds -ReadStartedAt $readStartedAt -NextAttemptAt $Tracker.nextAttemptAt
    if ($due.reread) { return (& $result "reread" "" $now $pending.Count) }
    if (-not $due.due) {
        if ($Tracker.problem -ne "" -and $now -lt $Tracker.nextAttemptAt) {
            return (& $result "pending" (Format-HordeDecisionNotifyPending -Problem $Tracker.problem -What $what -Count $pending.Count -At $Tracker.nextAttemptAt) $due.wakeAt $pending.Count)
        }
        return (& $result "waiting" ("waiting: " + $what + ", " + $(if ($pending.Count -eq 1) { "is" } else { "are" }) + " in the quiet period until " + $due.wakeAt.ToString("HH:mm:ss") + "Z") $due.wakeAt $pending.Count)
    }
    # DUE: the messenger, the seat, the message, the post.
    $problem = ""
    $messenger = $null
    $found = Find-HordeMessenger -Require $script:HordeDecisionNotifyMessengerNeeds
    if ($found.state -ceq "known") { $messenger = $found.value }
    elseif ($found.state -ceq "absent") { $problem = "no messenger on this machine can deliver to a session (" + $found.reason + ")" }
    else { $problem = "no messenger was chosen: " + $found.reason }
    $sessionId = ""
    if ($problem -eq "") {
        $where = $null
        try { $where = & $Seat } catch { $where = New-HordeUnknown -Reason "the seat could not be read" -ErrorRecord $_ }
        if ($null -eq $where -or "$($where.state)" -ceq "absent") { $problem = "no session holds the role of " + $script:HordeDecisionNotifyReader + ", so there is nobody to tell" }
        elseif ("$($where.state)" -cne "known") { $problem = "the " + $script:HordeDecisionNotifyReader + "'s session cannot be told: " + $where.reason }
        else { $sessionId = "$($where.value.sessionId)" }
    }
    $ids = @($pending | ForEach-Object { $_.message })
    $noticeId = Get-HordeDecisionNotifyMessageId -HordeHome $HordeHome -Ids $ids
    if ($problem -eq "") {
        $deviceId = ""
        try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { $problem = "this machine's device id could not be had: " + $_.Exception.Message }
        if ($problem -eq "") {
            $message = [pscustomobject]@{ messageId = $noticeId; sessionId = $sessionId; from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeDecisionNotifyFrom }; body = (Format-HordeDecisionNotifyNotice -Items $pending); ttlSeconds = $script:HordeDecisionNotifyTtlSeconds }
            $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
            if ($posted.state -ceq "known" -and $script:HordeDecisionNotifyStages -ccontains "$($posted.value.stage)") {
                $stamp = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $entries = @(@($record.entries) + @($pending | ForEach-Object { [pscustomobject]@{ question = [int]$_.question; message = $_.message; at = $stamp; notice = $noticeId } }))
                $Tracker.problem = ""; $Tracker.retryDelay = $script:HordeDecisionNotifyRetryFirstSeconds; $Tracker.nextAttemptAt = [datetime]::MinValue
                $said = "rang for " + $what + ", through messenger " + $messenger.name + " (" + $posted.value.stage + ")"
                # The record after the post: a crash or a failed write between the two leaves the set
                # untold, and the next pass posts the same notice, which the messenger keeps as one.
                try { Write-HordeDecisionNotifyRecord -Path $path -Entries $entries }
                catch { $said = $said + "; but the told record could not be written (" + $_.Exception.Message + "), so the next pass posts the same notice again, which the messenger keeps as one" }
                return (& $result "rang" $said $null 0)
            }
            if ($posted.state -ceq "known") {
                $why = $posted.value.PSObject.Properties["reason"]
                $problem = "messenger " + $messenger.name + " answered " + $posted.value.stage + $(if ($null -ne $why -and "$($why.Value)" -ne "") { ": " + $why.Value } else { "" })
            }
            else { $problem = "messenger " + $messenger.name + " did not take it: " + $posted.reason }
        }
    }
    # NOT SENT: nothing recorded; tried again after the back-off (header).
    $Tracker.problem = $problem
    $Tracker.nextAttemptAt = $now.AddSeconds($Tracker.retryDelay)
    $Tracker.retryDelay = [Math]::Min($Tracker.retryDelay * 2, $script:HordeDecisionNotifyRetryMostSeconds)
    return (& $result "pending" (Format-HordeDecisionNotifyPending -Problem $problem -What $what -Count $pending.Count -At $Tracker.nextAttemptAt) $Tracker.nextAttemptAt $pending.Count)
}

function Invoke-HordeDecisionNotifyLoop {
    # `horde decisions notify`: passes until stopped, writing one line each time what it says changes.
    # -Once: one pass. -Stop: a wait handle that, once set, asks it to stop (header, ASKED TO STOP).
    # -Status: a synchronized table it keeps said and running in, for the window beside it. -Clock,
    # -Sleep, -Inbox and -Seat are for a test. Throws, after its line, when the told record refuses.
    param([switch]$Once, $Stop = $null, $Status = $null, [scriptblock]$Clock = $null, [scriptblock]$Sleep = $null, [scriptblock]$Inbox = $null, [scriptblock]$Seat = $null)
    $hordeHome = Get-HordeHome
    $settings = Get-HordeDecisionNotifySettings -HordeHome $hordeHome
    if ($settings.state -ceq "refused") { throw ("notify was not started, because its settings file is refused:" + [Environment]::NewLine + ($settings.findings -join [Environment]::NewLine)) }
    $v = $settings.values
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    if ($null -eq $Sleep) { $Sleep = { param([double]$Seconds) $ms = [int][Math]::Max(50, $Seconds * 1000); if ($null -ne $Stop) { [void]$Stop.WaitOne($ms) } else { Start-Sleep -Milliseconds $ms } } }
    if ($null -ne $Status) { $Status["running"] = $true }
    $mutex = New-Object System.Threading.Mutex($false, ("Local\" + (Get-HordeDecisionNotifyName -HordeHome $hordeHome)))
    $held = $false
    try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) {
        $mutex.Dispose()
        $line = "not run: notify is already running for this home, and it rings for what waits"
        if ($null -ne $Status) { $Status["said"] = $line; $Status["running"] = $false }
        Write-Output $line
        return
    }
    $refused = ""
    try {
        $tracker = New-HordeDecisionNotifyTracker -QuietSeconds $v.quietSeconds
        $stopSince = $null; $lastSaid = ""; $lastMark = $null; $lastPassAt = [datetime]::MinValue; $wakeAt = [datetime]::MinValue; $force = $true; $last = $null
        while ($true) {
            $now = & $Clock
            if ($null -eq $stopSince -and $null -ne $Stop -and $Stop.WaitOne(0)) { $stopSince = $now; $force = $true }
            $mark = Get-HordeDecisionNotifyStoreMark
            if ($force -or $mark -cne $lastMark -or $now -ge $wakeAt -or ($now - $lastPassAt).TotalSeconds -ge $v.rereadSeconds) {
                $force = $false
                $last = Invoke-HordeDecisionNotifyPass -Tracker $tracker -Clock $Clock -Inbox $Inbox -Seat $Seat -HordeHome $hordeHome
                $lastMark = $mark; $lastPassAt = & $Clock
                # The quiet period ended while the store was being read: read again before ringing.
                if ($last.outcome -ceq "reread") { $force = $true; continue }
                $wakeAt = [datetime]::MaxValue
                if ($null -ne $last.wakeAt) { $wakeAt = [datetime]$last.wakeAt }
                if ($last.said -cne $lastSaid) {
                    $lastSaid = $last.said
                    if ($null -ne $Status) { $Status["said"] = $last.said }
                    Write-Output $last.said
                }
                if ($last.outcome -ceq "refused") { $refused = $last.said; break }
            }
            if ($Once) { break }
            if ($null -ne $stopSince) {
                $leave = ""
                if ($last.pending -eq 0) { $leave = "stopped: nothing is left to ring for" }
                elseif (-not ($last.outcome -ceq "waiting" -and $null -ne $last.wakeAt -and [datetime]$last.wakeAt -le $stopSince.AddSeconds($script:HordeDecisionNotifyLingerSeconds))) {
                    $leave = "stopped: " + $last.pending + " answer(s) left untold; they ring at the next start"
                }
                if ($leave -ne "") {
                    if ($null -ne $Status) { $Status["said"] = $leave }
                    Write-Output $leave
                    break
                }
            }
            $now = & $Clock
            $nap = [double]$v.pollSeconds
            if ($wakeAt -ne [datetime]::MaxValue) { $nap = [Math]::Min($nap, [Math]::Max(0.2, ($wakeAt - $now).TotalSeconds)) }
            & $Sleep $nap
        }
    }
    finally {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
        if ($null -ne $Status) { $Status["running"] = $false }
    }
    if ($refused -ne "") { throw $refused }
}

function Start-HordeDecisionNotifyBeside {
    # Notify beside a window (header): the loop in a PowerShell of its own inside this process, loading
    # this very file. Returns { shell; runspace; pending; stop; status }, or $null when it could not start.
    try {
        $stop = New-Object System.Threading.ManualResetEvent($false)
        $status = [hashtable]::Synchronized(@{ said = ""; running = $true; failed = "" })
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $shell = [System.Management.Automation.PowerShell]::Create()
        $shell.Runspace = $runspace
        [void]$shell.AddScript('param($File, $Stop, $Status) Set-StrictMode -Version Latest; try { . $File; Invoke-HordeDecisionNotifyLoop -Stop $Stop -Status $Status } catch { $Status["failed"] = $_.Exception.Message; $Status["said"] = $_.Exception.Message; $Status["running"] = $false }').AddArgument($script:HordeDecisionNotifyFile).AddArgument($stop).AddArgument($status)
        return [pscustomobject]@{ shell = $shell; runspace = $runspace; pending = $shell.BeginInvoke(); stop = $stop; status = $status }
    } catch { return $null }
}

function Stop-HordeDecisionNotifyBeside {
    # Ask the notify beside a window to stop, and wait for it at most -Seconds: it may stay to ring for
    # an answer still in its quiet period. Returns the last line it said.
    param([Parameter(Mandatory = $true)]$Helper, [int]$Seconds = 180)
    if ($null -eq $Helper) { return "" }
    try { [void]$Helper.stop.Set() } catch { }
    $ended = $false
    try { $ended = $Helper.pending.AsyncWaitHandle.WaitOne($Seconds * 1000) } catch { }
    if ($ended) { try { [void]$Helper.shell.EndInvoke($Helper.pending) } catch { } }
    else { try { $Helper.shell.Stop() } catch { }; $Helper.status["said"] = "stopped: it had not ended " + $Seconds + " s after it was asked, and was ended; what is untold rings at the next start" }
    $Helper.status["running"] = $false
    try { $Helper.shell.Dispose(); $Helper.runspace.Dispose(); $Helper.stop.Dispose() } catch { }
    return "$($Helper.status['said'])"
}
