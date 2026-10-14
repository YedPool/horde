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
# THE FOUNDER, VERIFIED - OR ONLY HIS LABEL (2026-10-12). An answer given on his phone was signed by his
# passkey, and the relay's decisions channel wrote that passkey's key id into the answer's record when it
# verified the signature (signedBy, decisions/Rules.ps1). For a set of such answers the notice says so,
# as from.verified = { kind founder; by passkey; keyId } (messengers/Port.ps1, A VERIFIED SENDER), which
# a messenger shows as it can. The key id comes from the record and from nothing else, and the claim is
# made only when ALL of this holds (Get-HordeDecisionNotifyVerified):
#   - EVERY answer of the set names its passkey by the rules (Get-HordeDecisionSigner: the route phone,
#     its evidence, a key id). One answer typed in the window, or one record written before records named
#     the passkey, and the whole notice is by label only: a notice is one message, and it never says
#     "verified" over an answer nobody verified.
#   - they name ONE passkey: from.verified names one, and a notice does not pick among two.
#   - THAT PASSKEY IS TRUSTED NOW, asked of relay's trust store as the notice is made
#     (Find-HordeRelayTrustedSender): a passkey revoked since the answer - a lost phone - is not named, and
#     neither is a key the store holds as a machine's, nor any key while the store cannot be read.
# Otherwise the notice goes exactly as before, wearing the label (fromLabel) and no more. When a record
# named a passkey or held evidence and the notice still went by label, the line says why; a set typed in
# the window says nothing, because nothing was withheld. The told record is unchanged by this.
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
# ONE PER HOME: a named mutex (Global\, ending in a fingerprint of the home). A second notify for the
# same home says so and leaves. GLOBAL, NOT LOCAL (review of PR 249, SHOULD 1): Local\ is one session's
# namespace, and the relay runner that turns the bell (channels/decisions) may run in session 0 - the
# supervisor starts it whether or not anyone is signed in - while the window's notify runs in the
# person's session; with a Local\ name each would hold its own and both would ring. Where the runtime
# lets it (Windows PowerShell 5.1), the mutex is made open to this account alone, so another account
# can neither take the bell nor hold it; elsewhere it has the default protection. A name some other
# account holds and this one cannot open is the bell held elsewhere: nothing rings from here. ASKED TO STOP (the window closed), it does not drop an answer still in
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
# The id recipe, shared with every sender that names a message by what it is about.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\TextUuid.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "messengers\Port.ps1")
# relay's trust store, read only: whether the passkey a record names is trusted now (header, THE FOUNDER,
# VERIFIED). Loading it costs about 250 ms (measured 2026-10-12, PowerShell 5.1).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "relay\Trust.ps1")
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
    @{ name = "fromLabel"; kind = "label"; default = "F"; what = "The hub label the notice is from: the founder's, F, unless the person who answers wears another." }
)
# The reader whose unread messages are rung for, and whose seat the notice goes to: the role that keeps
# the list, and the one actor the command line reads the inbox as (decisions/Console.ps1).
$script:HordeDecisionNotifyReader = "warchief"
$script:HordeDecisionNotifySpeaker = "founder"
# Who the notice is from: notify is no session, so it names itself, in session.deliver's session-id shape,
# and wears the label of the person whose answers it rings for (the setting fromLabel, F by default).
# The label is what a messenger that knows sessions by label reads as the sender; a messenger may hold
# a message whose sender it cannot place, and an id of notify's own is not a session it can place.
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
    if ($null -eq $parsed) { return (& $no "refused" "could not be read as JSON") }
    if ($parsed -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $parsed.PSObject.Properties["schemaVersion"] -or "$($parsed.schemaVersion)" -cne "1" -or $null -eq $parsed.PSObject.Properties["rung"]) { return (& $no "refused" "is not version 1 with a list named rung") }
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
    # AN ANSWER TO ONE PART OF A QUESTION SAYS WHICH: "question 28 (part b)", "question 28 (parts a and
    # c)". The letter is the part's name in the list, not a word of his: the notice still quotes nothing.
    param([object[]]$Items = @(), [string]$On = "on")
    $count = @($Items).Count
    $n = @($Items | ForEach-Object { [int]$_.question } | Sort-Object -Unique | ForEach-Object {
        $number = $_
        $letters = @($Items | Where-Object { [int]$_.question -eq $number -and $null -ne $_.PSObject.Properties["part"] -and "$($_.part)" -cmatch '\A[a-z]\z' } | ForEach-Object { "$($_.part)" } | Sort-Object -Unique)
        if ($letters.Count -eq 0) { "" + $number }
        elseif ($letters.Count -eq 1) { "" + $number + " (part " + $letters[0] + ")" }
        else { "" + $number + " (parts " + (($letters[0..($letters.Count - 2)]) -join ", ") + " and " + $letters[$letters.Count - 1] + ")" }
    })
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
    # numbers, in any order, hashed and written as a lowercase uuid (core/TextUuid.ps1).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string[]]$Ids)
    $key = "horde-decisions-notify`n" + [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant() + "`n" + ((@($Ids | Sort-Object { [long]$_ }) | ForEach-Object { "$_" }) -join ",")
    return (ConvertTo-HordeTextUuid -Text $key)
}

function Get-HordeDecisionNotifyUnread {
    # The founder's messages the warchief has not read, from an inbox answer: { ok; reason; items },
    # each item { question; message; at; route; evidence; signedBy; part } - route, evidence and signedBy as the message's
    # record holds them, "" where it holds none; part the letter of the one part answered, or "". The inbox only reads (decisions/Operations.ps1).
    param($Answer)
    if ($null -eq $Answer -or "$($Answer.state)" -cne "known") { return [pscustomobject]@{ ok = $false; reason = $(if ($null -ne $Answer) { "$($Answer.reason)" } else { "no answer" }); items = @() } }
    if ("$($Answer.value.outcome)" -cne "done") { return [pscustomobject]@{ ok = $false; reason = "$($Answer.value.reason)"; items = @() } }
    $items = @($Answer.value.messages | Where-Object { $null -ne $_ -and "$($_.message.speaker)" -ceq $script:HordeDecisionNotifySpeaker } | ForEach-Object {
        $held = @{}
        foreach ($name in @("route", "evidence", "signedBy", "part")) { $p = $_.message.PSObject.Properties[$name]; $held[$name] = $(if ($null -ne $p -and $p.Value -is [string]) { $p.Value } else { "" }) }
        [pscustomobject]@{ question = [int]$_.number; message = "" + [long]$_.message.sequence; at = "$($_.message.at)"; route = $held["route"]; evidence = $held["evidence"]; signedBy = $held["signedBy"]; part = $held["part"] }
    })
    return [pscustomobject]@{ ok = $true; reason = ""; items = $items }
}

function Get-HordeDecisionNotifyVerified {
    # Whether the notice for -Items may say it is from the founder, verified (header, THE FOUNDER,
    # VERIFIED): { verified; why; claimed }. verified is from.verified, or $null with why in words.
    # claimed says a record of the set named a passkey or held evidence, so a $null is worth a line.
    # -Trust answers, for a key id, relay's trust store's tristate for it now. Never throws.
    param([object[]]$Items = @(), [Parameter(Mandatory = $true)][scriptblock]$Trust)
    $claimed = (@($Items | Where-Object { "$($_.signedBy)" -ne "" -or "$($_.evidence)" -ne "" }).Count -gt 0)
    $no = { param([string]$Why) return [pscustomobject]@{ verified = $null; why = $Why; claimed = $claimed } }
    if (@($Items).Count -eq 0) { return (& $no "there is no answer in the set") }
    $keys = New-Object System.Collections.ArrayList
    foreach ($i in @($Items)) {
        $signer = Get-HordeDecisionSigner -Route "$($i.route)" -Evidence "$($i.evidence)" -SignedBy "$($i.signedBy)"
        if ($signer.keyId -ceq "") { return (& $no ("the founder's words under question " + $i.question + " (record " + $i.message + ") are not named as verified: " + $signer.why)) }
        if ($keys -cnotcontains $signer.keyId) { [void]$keys.Add($signer.keyId) }
    }
    if ($keys.Count -ne 1) { return (& $no ("the answers of this set were signed by " + $keys.Count + " passkeys (" + ($keys -join ", ") + "), and a notice names one")) }
    $keyId = [string]$keys[0]
    $trusted = $null
    try { $trusted = & $Trust $keyId } catch { $trusted = New-HordeUnknown -Reason $_.Exception.Message }
    if ($null -eq $trusted -or @("known", "absent") -cnotcontains "$($trusted.state)") { return (& $no ("the trust store could not say whether the passkey " + $keyId + " is trusted now" + $(if ($null -ne $trusted) { " (" + $trusted.reason + ")" } else { "" }))) }
    if ($trusted.state -ceq "absent") { return (& $no ("the passkey that signed is not trusted now: " + $trusted.reason)) }
    if ($null -eq $trusted.value -or "$($trusted.value.proof)" -cne "webauthn") { return (& $no ("the key " + $keyId + " is trusted as a machine's, not as a passkey of the founder's")) }
    return [pscustomobject]@{ verified = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = $keyId }; why = ""; claimed = $claimed }
}

function New-HordeDecisionNotifyTracker {
    # What one running notify keeps in memory: when it first saw each message, and the back-off; and the
    # label its notices wear, the setting fromLabel (its declared default when none is given).
    param([int]$QuietSeconds = 30, [string]$FromLabel = "")
    if ($FromLabel -eq "") { $FromLabel = @($script:HordeDecisionNotifySettings.settings | Where-Object { $_.name -ceq "fromLabel" })[0].default }
    return [pscustomobject]@{ quietSeconds = $QuietSeconds; fromLabel = $FromLabel; firstSeen = @{}; nextAttemptAt = [datetime]::MinValue; retryDelay = $script:HordeDecisionNotifyRetryFirstSeconds; problem = "" }
}

function Get-HordeDecisionNotifyName {
    # The name of the one notify of -HordeHome: fixed words and a fingerprint of the home's path.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant())) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return ("horde-" + $script:HordeDecisionNotifyModule + "-" + $hash.Substring(0, 16))
}

function Get-HordeDecisionNotifyMutexName {
    # The one bell of -HordeHome, in the namespace every session of this machine shares (the header).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return ("Global\" + (Get-HordeDecisionNotifyName -HordeHome $HordeHome))
}

function New-HordeDecisionNotifyMutex {
    # The bell's mutex, not yet held, or $null when it exists and this account may not open it.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $name = Get-HordeDecisionNotifyMutexName -HordeHome $HordeHome
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $rules = New-Object System.Security.AccessControl.MutexSecurity
        $rules.AddAccessRule((New-Object System.Security.AccessControl.MutexAccessRule($me.User, [System.Security.AccessControl.MutexRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
        $made = $false
        try { return [System.Threading.Mutex]::new($false, $name, [ref]$made, $rules) }
        catch [System.Management.Automation.MethodException] { return [System.Threading.Mutex]::new($false, $name) }
    } catch [System.UnauthorizedAccessException] { return $null }
    finally { $me.Dispose() }
}

function Get-HordeDecisionNotifyStoreMark {
    # A cheap look at whether the store changed, so the inbox is not read every few seconds: how many
    # files, and the last name. Only a hint; the inbox is read every rereadSeconds whatever it says.
    # -Root: a store other than this home's own (the relay run's, when it was given one).
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

function Format-HordeDecisionNotifyPending {
    # The line for a set that was not sent: the reason first, then that nothing is lost and when it is tried again.
    param([string]$Problem, [string]$What, [int]$Count, [datetime]$At)
    return ("pending: " + $Problem + ". " + $What + $(if ($Count -eq 1) { ", stays" } else { ", stay" }) + " untold, and nothing is lost: the next try is from " + $At.ToString("HH:mm:ss") + "Z.")
}

function Invoke-HordeDecisionNotifyPass {
    # ONE PASS: read the told record and the inbox, and ring for the set if it is due. Returns
    # { outcome; said; wakeAt; pending }: outcome nothing, waiting, reread, rang, pending or refused;
    # said the one plain line for it; wakeAt when to pass again ($null: no reason to); pending how many
    # answers wait untold. -Clock, -Inbox, -Seat and -Trust are for a test that hands in its own.
    param([Parameter(Mandatory = $true)]$Tracker, [scriptblock]$Clock = $null, [scriptblock]$Inbox = $null, [scriptblock]$Seat = $null, [string]$HordeHome = "", [scriptblock]$Trust = $null)
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    if ($null -eq $Inbox) { $Inbox = { return (Invoke-HordeDecision -Operation "inbox" -Request @{ actor = $script:HordeDecisionNotifyReader }) } }
    if ($null -eq $Seat) { $Seat = { return (Get-HordeRoleSeat -Role $script:HordeDecisionNotifyReader) } }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Trust) { $Trust = { param([string]$KeyId) return (Find-HordeRelayTrustedSender -HordeHome $HordeHome -KeyId $KeyId) } }
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
            $from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeDecisionNotifyFrom; label = $Tracker.fromLabel }
            # The founder, verified, or only his label (header): asked as the notice is made, never kept.
            $who = Get-HordeDecisionNotifyVerified -Items $pending -Trust $Trust
            if ($null -ne $who.verified) { $from | Add-Member -NotePropertyName "verified" -NotePropertyValue $who.verified }
            $message = [pscustomobject]@{ messageId = $noticeId; sessionId = $sessionId; from = $from; body = (Format-HordeDecisionNotifyNotice -Items $pending); ttlSeconds = $script:HordeDecisionNotifyTtlSeconds }
            $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
            if ($posted.state -ceq "known" -and $script:HordeDecisionNotifyStages -ccontains "$($posted.value.stage)") {
                $stamp = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $entries = @(@($record.entries) + @($pending | ForEach-Object { [pscustomobject]@{ question = [int]$_.question; message = $_.message; at = $stamp; notice = $noticeId } }))
                $Tracker.problem = ""; $Tracker.retryDelay = $script:HordeDecisionNotifyRetryFirstSeconds; $Tracker.nextAttemptAt = [datetime]::MinValue
                # WOKEN, OR ONLY QUEUED: the messenger's own word on its knock (messengers/Port.ps1, THE
                # WAKE WORD). The set is told either way - the notice is in the mailbox - and the line
                # says whether the warchief was woken for it or reads it at its next turn.
                $wake = Format-HordeMessengerWake -Answer $posted
                if ($wake -cne "") { $wake = "; " + $wake }
                $said = "rang for " + $what + ", through messenger " + $messenger.name + " (" + $posted.value.stage + $wake + ")"
                if ($null -ne $who.verified) {
                    $said = $said + "; as the founder, verified by his passkey " + $who.verified.keyId
                    # What the messenger says of it: one that cannot show a verified sender posts by label.
                    # Not a second time when the wake words above already hold its reason.
                    $note = $posted.value.PSObject.Properties["reason"]
                    if ($null -ne $note -and "$($note.Value)" -ne "" -and -not $wake.Contains("$($note.Value)")) { $said = $said + "; " + $note.Value }
                }
                elseif ($who.claimed) { $said = $said + "; by label only: " + $who.why }
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

function Invoke-HordeDecisionNotifyTurn {
    # ONE TURN OF THE BELL, FOR A CALLER THAT IS NOT THE LOOP: the relay runner's decisions channel
    # (channels/decisions), each time it turns. WHY (the founder's bug of 2026-10-12): the loop below runs
    # beside the decisions window, or when someone starts `horde decisions notify`. An answer the founder
    # gave FROM HIS PHONE with the window closed was written to the store by the relay runner and rang for
    # nobody: no notify was running. The runner is the process that is there whenever a phone answer
    # arrives, so it turns the bell itself - this same pass, the same quiet rule, told record, messenger
    # and notice, never a second implementation.
    #
    # ONE BELL A HOME. The loop holds the home's mutex for as long as it runs; this takes it for one
    # turn. When a loop holds it - the window is open - that loop rings and this does nothing
    # (outcome elsewhere). Two turns can never ring at once, and a set rung by either is in the told
    # record the other reads.
    #
    # -Memory is the caller's own table, kept between turns: the tracker (when each answer was first
    # seen, the back-off) and the last line said. Returns { outcome; said; againMs }: outcome the pass's
    # (nothing, waiting, rang, pending, refused), or elsewhere; said a line only when it is new and worth
    # a log's line (rang, pending, refused - not waiting, not nothing); againMs how soon to turn again
    # for the bell's sake (the end of the quiet period, the end of a back-off), 0 when there is no reason.
    # NOT EVERY TURN READS THE INBOX, as the loop does not: only when the store's mark changed, the time
    # the last pass asked for has come, or rereadSeconds have passed (outcome idle otherwise). Measured
    # 2026-10-12: a pass on every turn made an empty turn of the run longer than its 300 ms minimum.
    # -StoreRoot names the store when it is not this home's own. -Clock, -Inbox, -Seat and -Trust are the
    # pass's, for a test.
    param([Parameter(Mandatory = $true)][hashtable]$Memory, [string]$HordeHome = "", [string]$StoreRoot = "", [scriptblock]$Clock = $null, [scriptblock]$Inbox = $null, [scriptblock]$Seat = $null, [scriptblock]$Trust = $null)
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    if ($null -eq $Clock) { $Clock = { return [datetime]::UtcNow } }
    $answer = {
        param([string]$Outcome, [string]$Line, [int]$AgainMs)
        $said = ""
        if ($Line -cne "" -and $Line -cne "$($Memory['said'])") { $said = $Line }
        if ($Line -cne "") { $Memory["said"] = $Line }
        return [pscustomobject]@{ outcome = $Outcome; said = $said; againMs = $AgainMs }
    }
    $settings = Get-HordeDecisionNotifySettings -HordeHome $HordeHome
    if ($settings.state -ceq "refused") { return (& $answer "refused" ("the founder's answers are not rung for, because the notify settings file is refused: " + (@($settings.findings) -join "; ")) 0) }
    $v = $settings.values
    $tracker = $Memory["tracker"]
    if ($null -eq $tracker -or $tracker.quietSeconds -ne [int]$v.quietSeconds -or $tracker.fromLabel -cne "$($v.fromLabel)") {
        $fresh = New-HordeDecisionNotifyTracker -FromLabel $v.fromLabel -QuietSeconds $v.quietSeconds
        if ($null -ne $tracker) { $fresh.firstSeen = $tracker.firstSeen }
        $tracker = $fresh
        $Memory["tracker"] = $tracker
    }
    $now = & $Clock
    $mark = Get-HordeDecisionNotifyStoreMark -Root $StoreRoot
    $wakeAt = $Memory["wakeAt"]
    $due = (-not $Memory.ContainsKey("mark")) -or $mark -cne "$($Memory['mark'])" -or ($null -ne $wakeAt -and $now -ge [datetime]$wakeAt) -or ($now - [datetime]$Memory["passAt"]).TotalSeconds -ge $v.rereadSeconds
    if (-not $due) {
        $left = 0
        if ($null -ne $wakeAt) { $left = [int][Math]::Max(200, [Math]::Min(3600000, ([datetime]$wakeAt - $now).TotalMilliseconds)) }
        return [pscustomobject]@{ outcome = "idle"; said = ""; againMs = $left }
    }
    $mutex = New-HordeDecisionNotifyMutex -HordeHome $HordeHome
    if ($null -eq $mutex) { return [pscustomobject]@{ outcome = "elsewhere"; said = ""; againMs = 0 } }
    $mine = $false
    try { $mine = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $mine = $true }
    if (-not $mine) { $mutex.Dispose(); return [pscustomobject]@{ outcome = "elsewhere"; said = ""; againMs = 0 } }
    $last = $null
    try {
        # The quiet period can end while the store is being read: read again before ringing, a few times
        # at most, as the loop does.
        for ($i = 0; $i -lt 3; $i++) {
            $last = Invoke-HordeDecisionNotifyPass -Tracker $tracker -Clock $Clock -Inbox $Inbox -Seat $Seat -HordeHome $HordeHome -Trust $Trust
            if ($last.outcome -cne "reread") { break }
            Start-Sleep -Milliseconds 200
        }
    }
    finally {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
    $Memory["mark"] = $mark; $Memory["passAt"] = $now; $Memory["wakeAt"] = $last.wakeAt
    $again = 0
    if ($null -ne $last.wakeAt) { $again = [int][Math]::Max(200, [Math]::Min(3600000, ([datetime]$last.wakeAt - (& $Clock)).TotalMilliseconds)) }
    $line = ""
    if (@("rang", "pending", "refused") -ccontains $last.outcome) { $line = $last.said }
    if ($last.outcome -ceq "nothing") { $Memory["said"] = "" }
    return (& $answer $last.outcome $line $again)
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
    $mutex = New-HordeDecisionNotifyMutex -HordeHome $hordeHome
    $held = $false
    if ($null -ne $mutex) { try { $held = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true } }
    if (-not $held) {
        if ($null -ne $mutex) { $mutex.Dispose() }
        $line = "not run: notify is already running for this home, and it rings for what waits"
        if ($null -ne $Status) { $Status["said"] = $line; $Status["running"] = $false }
        Write-Output $line
        return
    }
    $refused = ""
    try {
        $tracker = New-HordeDecisionNotifyTracker -QuietSeconds $v.quietSeconds -FromLabel $v.fromLabel
        $stopSince = $null; $lastSaid = ""; $lastMark = $null; $lastPassAt = [datetime]::MinValue; $wakeAt = [datetime]::MinValue; $force = $true; $last = $null
        while ($true) {
            $now = & $Clock
            if ($null -eq $stopSince -and $null -ne $Stop -and $Stop.WaitOne(0)) { $stopSince = $now; $force = $true }
            $mark = Get-HordeDecisionNotifyStoreMark
            if ($force -or $mark -cne $lastMark -or $now -ge $wakeAt -or ($now - $lastPassAt).TotalSeconds -ge $v.rereadSeconds) {
                $force = $false
                $last = Invoke-HordeDecisionNotifyPass -Tracker $tracker -Clock $Clock -Inbox $Inbox -Seat $Seat -HordeHome $hordeHome
                $lastMark = $mark; $lastPassAt = & $Clock
                # The quiet period ended while the store was being read: read again before ringing, after
                # a moment, so that a clock that has not moved (a test's) cannot spin here.
                if ($last.outcome -ceq "reread") { $force = $true; & $Sleep 0.2; continue }
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
