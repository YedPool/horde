# channels/decisions - the decisions list on the founder's phone: a snapshot of the open questions out,
# his signed answers in (relay design 2026-10-09, PR plan item 6).
#
# OUT (the Tick). When the decisions store or the set of phone keys has changed since the last look,
# the open questions are read through decisions/Operations.ps1 (list, state open: the questions as the
# window shows them, with their fields, wording, thread counts and whose turn it is), sealed to every
# TRUSTED phone identity key of the horde (relay/Trust.ps1, Find-HordeRelayPhoneKeys) and put into the
# horde's phone mailbox, <horde>/phone - and only when the snapshot itself differs from the last one
# sent, so a change that shows nothing new (a read mark, a later-kind record) sends nothing.
#   - WHAT CHANGED IS ASKED CHEAPLY. Reading the list checks every record against its schemas (3.4 s for
#     81 records, measured 2026-10-06, decisions/Operations.ps1), so it is not done on every turn. The
#     store's records are write-once and named by their order, so the list of their NAMES changes
#     exactly when the list can; with the phone keys' ids it is the fingerprint asked each turn. The
#     names are listed, nothing is opened: decisions/Store.ps1 stays the only reader of a record.
#   - NO SECRET LEAVES THE MACHINE. Every question is put through decisions/Rules.ps1's
#     Find-HordeDecisionSecrets - the same refusal every request gets - before it goes in. A question
#     that trips it (a record written before a pattern was added, say) is WITHHELD: the snapshot says
#     its number and that it is shown at the machine only, and never what tripped it.
#   - THE LAST SNAPSHOT SENT is remembered for the run, as its hash. A new run sends one snapshot at its
#     first look whatever the last run sent: the phone shows the newest, so a repeat costs one envelope.
#   - A snapshot larger than an envelope's body (1 MiB) is not sent, and says so: splitting it is a
#     later change, and silently cutting the list would show the founder less than there is.
#
# IN (the Accept), kind answer, from the founder's trusted passkeys only. The body is the phone's JSON:
#   {"v":1,"answerId":"<32 hex>","number":<question>,"wordingVersion":<wording on screen>,"text":"..."}
# read strictly - no member repeated, none missing, none added - and put into the decisions list as the
# founder's words by the route phone (decisions/Rules.ps1), with the record's evidence: the hash of the
# relay journal record that proved them. The request's id is derived from the sender and the answerId:
#   id = the first 16 bytes of SHA-256("horde-relay/decisions/v1 answer id" LF <sender key id> LF <answerId>)
# so the same answer handed over again - a record resumed after a crash, or the phone sending it again
# in a new envelope because it heard nothing back - is the first record answered again (decisions'
# idempotency, which does not hash the evidence). THE FIRST ANSWER WINS: other words under one
# answerId are refused by the list, and that refusal is final. A window answer and a phone answer to
# one question are two answers, kept in store order (design Q15); neither erases the other.
#   done     the list answered done or replayed: the words are in the store, once;
#   refused  the list refused them, or there is no such question - final, with the list's reasons;
#   retry    the list could not be read or written (unknown): the record comes again.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Operations.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")

$script:HordeDecisionsChannelFolder = $PSScriptRoot
$script:HordeDecisionsChannelAnswerMembers = @("v", "answerId", "number", "wordingVersion", "text")
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
    # The phone's answer body, read strictly: { ok; reason; value } with value { answerId; number;
    # wordingVersion; text }. Never throws for the body: it was signed by the founder's passkey, but
    # the PWA that wrote it is code, and code has bugs.
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
    if (-not (Test-HordeDecisionCount -Value $a.number -Most (Get-HordeDecisionMaxNumber))) { $fail.reason = "the answer's number is not a question number"; return $fail }
    if (-not (Test-HordeDecisionCount -Value $a.wordingVersion -Most (Get-HordeDecisionMaxNumber))) { $fail.reason = "the answer's wordingVersion is not a wording"; return $fail }
    if ($a.text -isnot [string]) { $fail.reason = "the answer's text is not text"; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ answerId = $a.answerId; number = [int]$a.number; wordingVersion = [int]$a.wordingVersion; text = [string]$a.text } }
}

function Invoke-HordeDecisionsChannelAccept {
    # One opened answer into the decisions list (IN, in the header). { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeDecisionsChannelAnswer -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $request = @{
        id = (Get-HordeDecisionsChannelAnswerId -From $Item.from -AnswerId $r.value.answerId); actor = "founder"; number = $r.value.number
        speaker = "founder"; route = "phone"; text = $r.value.text; wordingVersion = $r.value.wordingVersion; evidence = $Item.evidence
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

function New-HordeDecisionsChannelSnapshot {
    # The snapshot's value from a list answer's value: the open questions, each put through the secret
    # refusal; a question that trips it is withheld, by number only.
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Machine, [Parameter(Mandatory = $true)]$List)
    $shown = New-Object System.Collections.ArrayList
    $withheld = New-Object System.Collections.ArrayList
    foreach ($q in @($List.questions)) {
        if (@(Find-HordeDecisionSecrets -Value $q).Count -gt 0) {
            [void]$withheld.Add([ordered]@{ number = [int]$q.number; reason = "it holds what looks like a secret, so it is shown at the machine only" })
            continue
        }
        [void]$shown.Add($q)
    }
    return [ordered]@{ v = 1; kind = "decisions-snapshot"; horde = $Horde; machine = $Machine; questions = @($shown.ToArray()); withheld = @($withheld.ToArray())
        counts = $List.counts; unreadable = @($List.unreadable).Count; notUnderstood = @($List.notUnderstood).Count }
}

function Invoke-HordeDecisionsChannelTick {
    # OUT, in the header: lines saying what was sent, or why not.
    param($Context)
    if (-not $Context.state.ContainsKey("decisions")) { $Context.state["decisions"] = @{ fingerprint = $null; sent = "" } }
    $mine = $Context.state["decisions"]
    $phones = Find-HordeRelayPhoneKeys -HordeHome $Context.hordeHome
    if ($phones.state -cne "known") { return @("no snapshot: " + $phones.reason) }
    $keys = @($phones.value)
    if ($keys.Count -eq 0) {
        if ($mine.fingerprint -cne "no phone") { $mine.fingerprint = "no phone"; return @("no snapshot: no phone identity key of this horde is trusted yet") }
        return @()
    }
    $root = $Context.decisionsRoot
    if ($root -ceq "") { $root = Get-HordeDecisionStoreRoot }
    $print = Get-HordeDecisionsChannelFingerprint -Root $root -PhoneKeyIds @($keys | ForEach-Object { $_.agreeKeyId })
    if ($print -cne "" -and $print -ceq $mine.fingerprint) { return @() }
    $list = Invoke-HordeDecision -Operation "list" -Request @{ state = "open" } -Root $Context.decisionsRoot
    if ($list.state -cne "known" -or $list.value.outcome -cne "done") { return @("no snapshot: the decisions list could not be read (" + $(if ($list.state -ceq "known") { $list.value.reason } else { $list.reason }) + ")") }
    $snap = New-HordeDecisionsChannelSnapshot -Horde $Context.horde -Machine $Context.signKeyId -List $list.value
    $text = ConvertTo-Json -InputObject $snap -Compress -Depth 20
    $body = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes $body)
    if ($hash -ceq $mine.sent) { $mine.fingerprint = $print; return @() }
    if ($body.Length -gt (Get-HordeRelayEnvelopeLimits).bodyBytes) { return @("no snapshot: it is " + $body.Length + " bytes, more than an envelope holds (" + (Get-HordeRelayEnvelopeLimits).bodyBytes + "); it is not cut") }
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    $sent = Send-HordeRelayChannelEnvelope -Context $Context -Channel "decisions" -Kind "snapshot" -Body $body -Recipients @($keys | ForEach-Object { ,([byte[]]$_.public) }) -Mailbox (New-HordeRelayMailbox -Horde $Context.horde -Reader "phone")
    if ($sent.state -cne "known") { return @("no snapshot: " + $sent.reason) }
    $mine.sent = $hash
    $mine.fingerprint = $print
    $w = @($snap.withheld).Count
    return @("snapshot of " + @($snap.questions).Count + " open question(s)" + $(if ($w -gt 0) { ", " + $w + " withheld" } else { "" }) + " sent to " + $keys.Count + " phone key(s) as " + $sent.value.key)
}

$null = Register-HordeRelayChannel -Folder $script:HordeDecisionsChannelFolder -Name "decisions" -Kinds @("answer") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeDecisionsChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeDecisionsChannelTick -Context $Context) }
