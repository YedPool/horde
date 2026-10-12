# channels/decisions - the decisions list on the founder's phone: a snapshot of the open questions out,
# his signed answers in (relay design 2026-10-09, PR plan item 6).
#
# OUT (the Tick). When the decisions store or the set of phone keys has changed since the last look,
# the open questions are read through decisions/Operations.ps1 - list, state open, WITH MESSAGES: every
# field of each question (its text, its context, the recommendation, its parts, its options, its
# references), its wording, and its whole conversation with the warchief's replies and whose turn it
# is, which is what the founder needs to answer from the phone (review of 48bc492, item 9). It is
# sealed to every TRUSTED phone identity key of the horde (relay/Trust.ps1, Find-HordeRelayPhoneKeys)
# and put into the horde's phone mailbox, <horde>/phone - and only when the snapshot itself differs
# from the last one sent, so a change that shows nothing new (a read mark, a later-kind record) sends
# nothing.
#   - WHAT CHANGED IS ASKED CHEAPLY. Reading the list checks every record against its schemas (3.4 s for
#     81 records, measured 2026-10-06, decisions/Operations.ps1), so it is not done on every turn. The
#     store's records are write-once and named by their order, so the list of their NAMES changes
#     exactly when the list can; with the phone keys' ids it is the fingerprint asked each turn. The
#     names are listed, nothing is opened: decisions/Store.ps1 stays the only reader of a record.
#   - WHAT IS THE WARCHIEF'S IS LEFT OUT: which messages the warchief has not read (each message's
#     unreadBy, each thread's unread). It is his inbox, not the founder's, and keeping it would send a
#     new snapshot for every read mark.
#   - NO SECRET LEAVES THE MACHINE. Every question is put through decisions/Rules.ps1's
#     Find-HordeDecisionSecrets - the same refusal every request gets - before it goes in. A question
#     that trips it (a record written before a pattern was added, say) is WITHHELD: the snapshot says
#     its number and that it is shown at the machine only, and never what tripped it.
#   - PAGES. A snapshot is one envelope when it fits, and pages when it does not: each page an envelope
#     whose body is within what the envelope and the relay hold (channels/Port.ps1,
#     Get-HordeRelayChannelBodyBudget), each carrying the snapshot's hash, its number and how many there
#     are, so the phone puts one snapshot together. A question larger than a page by itself is WITHHELD
#     by number as too large - never cut, which would show the founder less than there is.
#   - RECORDED ONCE, PUT UNTIL IT IS TAKEN (review of 48bc492, finding 1). Every page is recorded in the
#     journal first (its seq is spent) and kept in the channel's memory until the relay takes it; a
#     relay that will not take it is asked again, with the SAME envelope, on the next turn - no new
#     snapshot is made while one is waiting - and the tick says it failed, so the runner backs off.
#   - THE LAST SNAPSHOT SENT is remembered in the run's context, as its hash, and so is what is waiting
#     to be put; the context's hourly reopen keeps both (channels/Port.ps1, Update-HordeRelayRunContext).
#     A new run sends one snapshot at its first look whatever the last run sent: the phone shows the
#     newest, so a repeat costs one envelope.
#
# IN (the Accept), kind answer, from the founder's trusted passkeys only. The body is the phone's JSON:
#   {"v":1,"answerId":"<32 hex>","machine":"<32 hex>","snapshot":"<replay key>","number":<question>,
#    "wordingVersion":<wording on screen>,"text":"..."}
# read strictly - no member repeated, none missing, none added.
#   - AN ANSWER IS FOR ONE MACHINE (review of 48bc492, finding 2): question 1 of one machine is not
#     question 1 of another, and one envelope may be sealed to several. machine is the key id of the
#     machine whose snapshot the founder answered, and snapshot the replay key of that snapshot's
#     envelope (the page that carried the question). An answer is taken only when machine is THIS
#     machine and its journal holds that snapshot as sent (relay/Journal.ps1, Test-HordeRelayJournalSent).
#     The replay key rather than the snapshot's hash: the journal answers for a key at once, and a hash
#     would need every snapshot this machine ever sent kept somewhere.
#   - It is then put into the decisions list as the founder's words by the route phone
#     (decisions/Rules.ps1), with the record's evidence: the hash of the relay journal record that proved
#     them, and signedBy: the key id of the passkey the envelope's signature was verified against - the
#     envelope's sender, which the port's gate checked before this Accept ran, never anything the
#     answer's own text says. It is written once, here, so that whoever tells the warchief of the answer
#     can name the founder as verified from the record alone (decisions/Notify.ps1). A READER OLDER THAN
#     THE MEMBER (before 2026-10-12) finds such a record unreadable, as its schema admits no member it
#     does not list (measured 2026-10-12 with the tree of PR #180: show and inbox left the answer out and
#     counted it unreadable): every checkout that reads the list is moved first, the relay's runner last.
#     The request's id is derived from the sender and the answerId:
#       id = the first 16 bytes of SHA-256("horde-relay/decisions/v1 answer id" LF <sender key id> LF <answerId>)
#     so the same answer handed over again - a record resumed after a crash, or the phone sending it
#     again in a new envelope because it heard nothing back - is the first record answered again
#     (decisions' idempotency, which does not hash the evidence). THE FIRST ANSWER WINS: other words
#     under one answerId are refused by the list, and that refusal is final. A window answer and a phone
#     answer to one question are two answers, kept in store order (design Q15); neither erases the other.
#   done     the list answered done or replayed: the words are in the store, once;
#   refused  for another machine, or a snapshot this machine never sent, or the list refused them, or
#            there is no such question - final, with the reason;
#   retry    the list or the journal could not be read (unknown): the record comes again.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Operations.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")

$script:HordeDecisionsChannelFolder = $PSScriptRoot
$script:HordeDecisionsChannelAnswerMembers = @("v", "answerId", "machine", "snapshot", "number", "wordingVersion", "text")
$script:HordeDecisionsChannelIdDomain = "horde-relay/decisions/v1 answer id"

function Get-HordeDecisionsChannelAnswerId {
    # The decisions request id of one answer (the header): 32 lower-case hex.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$AnswerId)
    $h = Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ($script:HordeDecisionsChannelIdDomain + "`n" + $From + "`n" + $AnswerId))
    $first = New-Object byte[] 16
    [System.Array]::Copy($h, 0, $first, 0, 16)
    return (ConvertTo-HordeRelayHex -Bytes $first)
}

function Read-HordeDecisionsChannelAnswer {
    # The phone's answer body, read strictly: { ok; reason; value } with value { answerId; machine;
    # snapshot; number; wordingVersion; text }. Never throws for the body: it was signed by the founder's
    # passkey, but the PWA that wrote it is code, and code has bugs.
    param([AllowEmptyCollection()][byte[]]$Body)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the answer is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the answer is not a JSON object"; return $fail }
    $dups = @(Find-HordeJsonDuplicateKey -Text $text)
    if ($dups.Count -gt 0) { $fail.reason = ("the answer has a member more than once: " + $dups[0]); return $fail }
    try { $a = ConvertFrom-Json -InputObject $text } catch { $fail.reason = "the answer is not JSON"; return $fail }
    if ($a -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the answer is not a JSON object"; return $fail }
    $names = @($a.PSObject.Properties | ForEach-Object { $_.Name })
    if ((@($names | Sort-Object) -join ",") -cne (@($script:HordeDecisionsChannelAnswerMembers | Sort-Object) -join ",")) { $fail.reason = ("the answer's members are " + ($names -join ", ") + ", not " + ($script:HordeDecisionsChannelAnswerMembers -join ", ")); return $fail }
    if (-not ($a.v -is [int] -or $a.v -is [long]) -or $a.v -ne 1) { $fail.reason = "the answer is not version 1"; return $fail }
    if ($a.answerId -isnot [string] -or $a.answerId -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the answer's answerId is not 32 lower-case hex"; return $fail }
    if ($a.machine -isnot [string] -or $a.machine -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the answer's machine is not a key id"; return $fail }
    if ($a.snapshot -isnot [string] -or $a.snapshot.Length -gt 160) { $fail.reason = "the answer's snapshot is not an envelope's replay key"; return $fail }
    if (-not (Test-HordeDecisionCount -Value $a.number -Most (Get-HordeDecisionMaxNumber))) { $fail.reason = "the answer's number is not a question number"; return $fail }
    if (-not (Test-HordeDecisionCount -Value $a.wordingVersion -Most (Get-HordeDecisionMaxNumber))) { $fail.reason = "the answer's wordingVersion is not a wording"; return $fail }
    if ($a.text -isnot [string]) { $fail.reason = "the answer's text is not text"; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ answerId = $a.answerId; machine = $a.machine; snapshot = $a.snapshot; number = [int]$a.number; wordingVersion = [int]$a.wordingVersion; text = [string]$a.text } }
}

function Invoke-HordeDecisionsChannelAccept {
    # One opened answer into the decisions list (IN, in the header). { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeDecisionsChannelAnswer -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    if ($r.value.machine -cne $Context.signKeyId) { return [pscustomobject]@{ outcome = "refused"; reason = ("the answer is for another machine (" + $r.value.machine + "), not this one (" + $Context.signKeyId + ")") } }
    $made = Test-HordeRelayJournalSent -Key $r.value.snapshot -HordeHome $Context.hordeHome
    if ($made.state -cne "known") { return [pscustomobject]@{ outcome = "retry"; reason = ("the journal cannot say whether this machine sent the snapshot the answer names: " + $made.reason) } }
    if (-not $made.value.sent -or $made.value.kind -cne "snapshot" -or -not $r.value.snapshot.StartsWith($Context.signKeyId + "/decisions/")) {
        return [pscustomobject]@{ outcome = "refused"; reason = ("the snapshot the answer names (" + $r.value.snapshot + ") is not a snapshot this machine sent") }
    }
    $request = @{
        id = (Get-HordeDecisionsChannelAnswerId -From $Item.from -AnswerId $r.value.answerId); actor = "founder"; number = $r.value.number
        speaker = "founder"; route = "phone"; text = $r.value.text; wordingVersion = $r.value.wordingVersion; evidence = $Item.evidence
        # WHO SIGNED, WRITTEN ONCE: the key id the relay verified this envelope's passkey signature against
        # (channels/Port.ps1's gate; senders founder, so a passkey's and never a machine's). The record
        # keeps it, and notify names the founder as verified from the record alone (decisions/Notify.ps1).
        signedBy = $Item.from
    }
    $a = Invoke-HordeDecision -Operation "say" -Request $request -Root $Context.decisionsRoot
    if ($a.state -ceq "unknown") { return [pscustomobject]@{ outcome = "retry"; reason = ("the decisions list could not take it now: " + $a.reason) } }
    if ($a.state -ceq "absent") { return [pscustomobject]@{ outcome = "refused"; reason = ("the decisions list refused it: " + $a.reason) } }
    if ($a.value.outcome -ceq "refused") { return [pscustomobject]@{ outcome = "refused"; reason = ("the decisions list refused it: " + (@($a.value.findings) -join "; ")) } }
    return [pscustomobject]@{ outcome = "done"; reason = ("question " + $r.value.number + ": the founder's answer is record " + $a.value.sequence + " (" + $a.value.outcome + ")") }
}

function Get-HordeDecisionsChannelFingerprint {
    # What decides whether the list may have changed (OUT, in the header): the store's record names and
    # the phone keys' ids. "" when the store cannot be listed - then the next turn asks again.
    param([string]$Root, [string[]]$PhoneKeyIds)
    $names = @()
    try {
        if ([System.IO.Directory]::Exists($Root)) { $names = @([System.IO.Directory]::GetFiles($Root, "*.json") | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Sort-Object) }
    } catch { return "" }
    return ((@($names) -join ",") + "|" + (@($PhoneKeyIds) -join ","))
}

function ConvertTo-HordeDecisionsChannelQuestion {
    # One question of the list as the phone gets it, as JSON text: the view less what is the warchief's
    # inbox (OUT, in the header).
    param($Question)
    $q = (ConvertTo-Json -InputObject $Question -Compress -Depth 20) | ConvertFrom-Json
    if ($null -ne $q.PSObject.Properties["thread"]) {
        if ($null -ne $q.thread.PSObject.Properties["unread"]) { $q.thread.PSObject.Properties.Remove("unread") }
        if ($null -ne $q.thread.PSObject.Properties["messages"]) { foreach ($m in @($q.thread.messages)) { if ($null -ne $m.PSObject.Properties["unreadBy"]) { $m.PSObject.Properties.Remove("unreadBy") } } }
    }
    return (ConvertTo-Json -InputObject $q -Compress -Depth 20)
}

function New-HordeDecisionsChannelPages {
    # The snapshot as page bodies (OUT, in the header): { hash; bodies; shown; withheld }. -Budget is the
    # largest body one page may have.
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Machine, [Parameter(Mandatory = $true)]$List, [Parameter(Mandatory = $true)][long]$Budget)
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $shown = New-Object System.Collections.ArrayList
    $withheld = New-Object System.Collections.ArrayList
    foreach ($q in @($List.questions)) {
        if (@(Find-HordeDecisionSecrets -Value $q).Count -gt 0) {
            [void]$withheld.Add([ordered]@{ number = [int]$q.number; reason = "it holds what looks like a secret, so it is shown at the machine only" })
            continue
        }
        $text = ConvertTo-HordeDecisionsChannelQuestion -Question $q
        [void]$shown.Add([pscustomobject]@{ number = [int]$q.number; text = $text; bytes = $utf8.GetByteCount($text) })
    }
    $tail = ',"counts":' + (ConvertTo-Json -InputObject $List.counts -Compress) + ',"unreadable":' + @($List.unreadable).Count + ',"notUnderstood":' + @($List.notUnderstood).Count + '}'
    # The frame of a page with no question: everything but the questions, the withheld ones counted at
    # their largest (every question withheld, each with the longest reason), and the page numbers at
    # nine digits. A question fits a page when its bytes and the frame are within the budget.
    $frameBytes = $utf8.GetByteCount('{"v":1,"kind":"decisions-snapshot","horde":"' + $Horde + '","machine":"' + $Machine + '","snapshot":"' + ("0" * 64) + '","page":999999999,"pages":999999999,"questions":[],"withheld":[]' + $tail) + 160 * (@($List.questions).Count + 1)
    $fitting = New-Object System.Collections.ArrayList
    foreach ($s in $shown) {
        if ($s.bytes + $frameBytes -gt $Budget) {
            [void]$withheld.Add([ordered]@{ number = $s.number; reason = ("it is too large to send to the phone (" + $s.bytes + " bytes; a page holds " + ($Budget - $frameBytes) + "), so it is shown at the machine only") })
            continue
        }
        [void]$fitting.Add($s)
    }
    $withheldText = ConvertTo-Json -InputObject @($withheld.ToArray()) -Compress -Depth 4
    if (@($withheld).Count -eq 0) { $withheldText = "[]" }
    elseif (@($withheld).Count -eq 1 -and -not $withheldText.StartsWith("[")) { $withheldText = "[" + $withheldText + "]" }
    $hash = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes $utf8.GetBytes(((@($fitting) | ForEach-Object { $_.text }) -join ",") + "|" + $withheldText + "|" + $tail))
    # Greedy, in the list's order: a page takes questions while they fit.
    $groups = New-Object System.Collections.ArrayList
    $current = New-Object System.Collections.ArrayList
    $used = $frameBytes
    foreach ($s in $fitting) {
        if ($current.Count -gt 0 -and $used + $s.bytes + 1 -gt $Budget) { [void]$groups.Add(@($current.ToArray())); $current = New-Object System.Collections.ArrayList; $used = $frameBytes }
        [void]$current.Add($s)
        $used += $s.bytes + 1
    }
    if ($current.Count -gt 0 -or $groups.Count -eq 0) { [void]$groups.Add(@($current.ToArray())) }
    $bodies = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $groups.Count; $i++) {
        $qs = (@($groups[$i]) | ForEach-Object { $_.text }) -join ","
        $page = '{"v":1,"kind":"decisions-snapshot","horde":"' + $Horde + '","machine":"' + $Machine + '","snapshot":"' + $hash + '","page":' + ($i + 1) + ',"pages":' + $groups.Count + ',"questions":[' + $qs + '],"withheld":' + $withheldText + $tail
        [void]$bodies.Add($utf8.GetBytes($page))
    }
    return [pscustomobject]@{ hash = $hash; bodies = @($bodies.ToArray()); shown = $fitting.Count; withheld = @($withheld).Count }
}

function Send-HordeDecisionsChannelPending {
    # Put what is recorded and waiting, in order. "" when everything was taken, else why not.
    param($Context, $Mine)
    while ($Mine.pending.Count -gt 0) {
        $p = $Mine.pending[0]
        $put = Send-HordeRelayChannelSaved -Context $Context -Saved $p -Mailbox $p.mailbox
        if ($put.state -cne "known") { return $put.reason }
        $Mine.pending.RemoveAt(0)
    }
    return ""
}

function Invoke-HordeDecisionsChannelTick {
    # OUT, in the header: { lines; failed }.
    param($Context)
    if (-not $Context.state.ContainsKey("decisions")) { $Context.state["decisions"] = @{ fingerprint = $null; sent = ""; pending = (New-Object System.Collections.ArrayList) } }
    $mine = $Context.state["decisions"]
    # What was recorded and not taken, first: the same envelopes, never new ones.
    if ($mine.pending.Count -gt 0) {
        $why = Send-HordeDecisionsChannelPending -Context $Context -Mine $mine
        if ($why -cne "") { return [pscustomobject]@{ lines = @("snapshot not delivered yet (" + $mine.pending.Count + " envelope(s) recorded and waiting): " + $why); failed = $true } }
    }
    $phones = Find-HordeRelayPhoneKeys -HordeHome $Context.hordeHome
    if ($phones.state -cne "known") { return [pscustomobject]@{ lines = @("no snapshot: " + $phones.reason); failed = $true } }
    $keys = @($phones.value)
    if ($keys.Count -eq 0) {
        if ($mine.fingerprint -cne "no phone") { $mine.fingerprint = "no phone"; return [pscustomobject]@{ lines = @("no snapshot: no phone identity key of this horde is trusted yet"); failed = $false } }
        return [pscustomobject]@{ lines = @(); failed = $false }
    }
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    $root = $Context.decisionsRoot
    if ($root -ceq "") { $root = Get-HordeDecisionStoreRoot }
    $print = Get-HordeDecisionsChannelFingerprint -Root $root -PhoneKeyIds @($keys | ForEach-Object { $_.agreeKeyId })
    if ($print -cne "" -and $print -ceq $mine.fingerprint) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $list = Invoke-HordeDecision -Operation "list" -Request @{ state = "open"; messages = $true } -Root $Context.decisionsRoot
    if ($list.state -cne "known" -or $list.value.outcome -cne "done") { return [pscustomobject]@{ lines = @("no snapshot: the decisions list could not be read (" + $(if ($list.state -ceq "known") { $list.value.reason } else { $list.reason }) + ")"); failed = $true } }
    $budget = Get-HordeRelayChannelBodyBudget -Context $Context -Recipients $keys.Count
    $pages = New-HordeDecisionsChannelPages -Horde $Context.horde -Machine $Context.signKeyId -List $list.value -Budget $budget
    if ($pages.hash -ceq $mine.sent) { $mine.fingerprint = $print; return [pscustomobject]@{ lines = @(); failed = $false } }
    $mailbox = New-HordeRelayMailbox -Horde $Context.horde -Reader "phone"
    $recipients = @($keys | ForEach-Object { , ([byte[]]$_.public) })
    $keysSent = New-Object System.Collections.ArrayList
    foreach ($body in @($pages.bodies)) {
        $saved = Save-HordeRelayChannelEnvelope -Context $Context -Channel "decisions" -Kind "snapshot" -Body ([byte[]]$body) -Recipients $recipients
        if ($saved.state -cne "known") { return [pscustomobject]@{ lines = @("no snapshot: " + $saved.reason); failed = $true } }
        $saved.value | Add-Member -NotePropertyName "mailbox" -NotePropertyValue $mailbox
        [void]$mine.pending.Add($saved.value)
        [void]$keysSent.Add($saved.value.key)
    }
    # Every page is recorded: this snapshot is the one sent, whatever the relay does next.
    $mine.sent = $pages.hash
    $mine.fingerprint = $print
    $what = "snapshot of " + $pages.shown + " open question(s)" + $(if ($pages.withheld -gt 0) { ", " + $pages.withheld + " withheld" } else { "" }) + " in " + @($pages.bodies).Count + " page(s) for " + $keys.Count + " phone key(s), as " + ($keysSent -join ", ")
    $why = Send-HordeDecisionsChannelPending -Context $Context -Mine $mine
    if ($why -cne "") { return [pscustomobject]@{ lines = @($what + " recorded; not delivered yet: " + $why); failed = $true } }
    return [pscustomobject]@{ lines = @($what + " sent"); failed = $false }
}

$null = Register-HordeRelayChannel -Folder $script:HordeDecisionsChannelFolder -Name "decisions" -Kinds @("answer") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeDecisionsChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeDecisionsChannelTick -Context $Context) }
