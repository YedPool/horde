# channels/decisions - the decisions list on the founder's phone: a snapshot of the open questions out,
# his signed answers in (relay design 2026-10-09, PR plan item 6).
#
# OUT (the Tick). When the decisions store or the set of phone keys has changed since the last look,
# the open questions are read through decisions/Operations.ps1 - list, state open, WITH MESSAGES: every
# field of each question (its text, its context, the recommendation, its parts, its options, its
# references), how much it matters and how much it blocks (importance, blocks and their plain words),
# the question it follows up with what he answered there, its wording, and its whole conversation with the warchief's replies and whose turn it
# is, which is what the founder needs to answer from the phone (review of 48bc492, item 9). It is
# sealed to every TRUSTED phone identity key of the horde (relay/Trust.ps1, Find-HordeRelayPhoneKeys)
# and put into the horde's phone mailbox, <horde>/phone - and only when the snapshot itself, or the set
# of phones it is sealed to, differs from the last one sent, so a change that shows nothing new (a read
# mark, a later-kind record) sends nothing.
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
#   - THE SNAPSHOT BEFORE IS DEAD WEIGHT THE MOMENT THIS ONE IS WHOLE IN THE MAILBOX, AND ONLY THEN
#     (2026-10-13). The phone shows the newest complete snapshot and nothing of an older one; nobody
#     acks the phone's mailbox, so every snapshot ever sent stayed in it until the relay's retention,
#     and the hosted relay refuses every put once a mailbox holds 2,000 envelopes. So the put of a
#     snapshot's LAST page says to keep, of this machine's decisions envelopes, from the snapshot's
#     FIRST page on (channels/Port.ps1, WHAT GOES TO THE PHONE IS TRIMMED BY ITS SENDER): everything
#     this machine sent on the channel before it goes. It rides on the last page and on no other,
#     because pages are put in order and each is put only once the one before was taken: while any
#     page is still waiting, the snapshot before is the newest whole one there is, and it stays. A
#     PHONE PAIRED LATER LOSES NOTHING by it: what was sent before its key was trusted was never
#     sealed to it, and its key changes the fingerprint, so a snapshot sealed to it too is sent.
#   - EVERY OTHER PAGE KEEPS FROM THE LAST SNAPSHOT THE RELAY WHOLLY TOOK (review of PR 232, 2026-10-14).
#     The first seq of that snapshot is remembered where it survives a restart
#     (<HORDE_HOME>\relay\decisions\state.json: the machine's key id and that one number, replaced whole
#     in one rename), written when a snapshot's last page is taken. A page that is not the last says
#     to keep from it: what is older than a whole snapshot is dead weight whatever becomes of this
#     one, so that trim can never leave the phone with none. A memory that is not there, cannot be
#     read, is another key's (the identity was rotated) or names a seq past the page's own is no
#     memory, and such a page then says nothing, as before.
#   - A FULL MAILBOX IS EMPTIED BY ONE PAGE SENT FIRST (the same review: without this the mailbox this
#     was built to rescue could never be rescued). A mailbox at its cap refuses page 1 of a snapshot of
#     several pages (507); pages go in order, so the last page - the only one whose trim makes room -
#     was never sent, on every turn and after every restart. WHAT WAS LOOKED AT AND DOES NOT WORK: the
#     last page first (it deletes the snapshot before while this one is not whole); the memory above
#     (in exactly this case there is none: a snapshot that landed under this code already emptied the
#     mailbox); the journal (it records an envelope BEFORE the relay is asked, relay/Journal.ps1, so
#     it says what was made and never what was taken, and a page's number is inside its sealed body);
#     and reading the mailbox back (the machine cannot open what it sealed to the phones). WHAT DOES:
#     a snapshot of ONE page is its own last page - its put carries its own trim, and the relay counts
#     what a trim frees before it asks its caps and writes the item before it deletes anything. So
#     when a page that is not the last is refused as full, the pages waiting are let go (their seqs
#     are spent; any the relay took are deleted with the rest) and ONE page is sent: the questions
#     that fit it, and every other open question withheld BY NUMBER, saying it is in the snapshot that
#     follows. It is true, it is whole, and it empties this machine's decisions stream; the full
#     snapshot is then sent in the same look, into the room that made, and replaces it. The phone
#     shows the short one for about as long as that takes. ONCE A RUN, until a snapshot of several
#     pages has landed: a mailbox still full after it is full of something this channel cannot trim,
#     and that is the runner's to say out loud (cli/RelayRun.ps1), not a reason to send it again.
#   - THE LAST SNAPSHOT SENT is remembered in the run's context, as its hash and the phone keys it was
#     sealed to (a phone paired while the list stands still is sent the same snapshot, sealed to it:
#     nothing sent before was), and so is what is waiting
#     to be put; the context's hourly reopen keeps both (channels/Port.ps1, Update-HordeRelayRunContext).
#     A new run sends one snapshot at its first look whatever the last run sent: the phone shows the
#     newest, so a repeat costs one envelope.
#
# IN (the Accept), kind answer, from the founder's trusted passkeys only. The body is the phone's JSON:
#   {"v":1,"answerId":"<32 hex>","machine":"<32 hex>","snapshot":"<replay key>","number":<question>,
#    "wordingVersion":<wording on screen>,"text":"..."}
# read strictly - no member repeated, none missing, none added.
#   - AN ANSWER TO ONE PART OF A QUESTION IS VERSION 2: the same members and, last, "part": the letter
#     of the part the words answer (the founder, 2026-10-12: each part sends by itself). It goes into
#     the list as its own record naming that part (decisions/Rules.ps1, A QUESTION OF PARTS). Version 1
#     is read as it always was - a phone that does not know parts sends it for all the parts at once -
#     and each version is held to exactly its own members: a part in a version 1 body, or none in a
#     version 2, is refused. THE SNAPSHOT SAYS WHICH VERSIONS THIS MACHINE READS ("answers":2, the
#     highest), so that a phone sends a part as version 2 only to a machine that takes it, and to an
#     earlier machine - whose snapshot says nothing - as the words "(b) ..." in version 1.
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
# WHAT BECAME OF EACH ANSWER GOES BACK TO THE PHONE (the founder, 2026-10-14, relay fixes 3 and 4). After
# a restart of the PC the runner was down 2 h 38 min; twenty of his answers waited on the relay, the
# phone showed nothing of them, and one phone envelope, decisions/16, never arrived and nothing said so.
# WHY 16 COULD VANISH: not the relay's retention (the hosted relay keeps an unacked item 30 days) and not a
# trim (a trim deletes only its putter's OWN stream in the PHONE's mailbox, channels/Port.ps1; answers go
# into the MACHINE's mailbox, which only this machine acks, after journaling). The phone spends a seq
# BEFORE the passkey signs and before the put (surfaces/pwa/page/phone-core.js, sealAndSign): a prompt
# cancelled or timed out, or a put that failed, leaves a seq no envelope ever carried - a hole the
# journal reports as missing when the next one lands, and the words are sent again under a new seq.
# And an envelope that DOES arrive after a later one of its phone is refused for good as out of order
# (relay/Journal.ps1), so a real loss heals only by a new envelope. Either way the phone never knew.
# SO EVERY SNAPSHOT CARRIES RECEIPTS, a member of every page ("receipts", in the frame and the hash, so
# a change of them is a new snapshot): for each founder passkey that sent this machine an answer -
#   from      the passkey's key id: the phone reads only its own;
#   through   the highest seq of that passkey's decisions stream the journal holds: every answer the
#             phone put under a seq at or below it, and not missing, is RECEIVED BY THE PC;
#   missing   the seqs below through the journal never recorded (the newest 32, within 4096): the
#             phone resends an answer it put under one of them, as a new envelope;
#   applied   the answerIds the list took (Accept done: the store holds the record), newest 64;
#   refused   the answerIds refused for good, newest 16; an id applied is never listed refused.
# IDS AND NUMBERS ONLY, NEVER AN ANSWER'S WORDS. The journal answers through and missing by listing its
# stream (one record read); applied and refused are a ledger Accept keeps, by answerId, in
# <HORDE_HOME>\relay\decisions\receipts.json, replaced whole in one rename, so a restart forgets none.
# The receipts are asked on every look, and a change of them sends a snapshot as a change of the list
# does. A RESENT ANSWER IS APPLIED ONCE: its request id is derived from the passkey and the answerId
# (above), so the second envelope is the first record answered again.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Operations.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Notify.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")

$script:HordeDecisionsChannelFolder = $PSScriptRoot
$script:HordeDecisionsChannelAnswerMembers = @("v", "answerId", "machine", "snapshot", "number", "wordingVersion", "text")
# THE ANSWER'S VERSIONS, each with the one member it adds to those above (header, IN). The highest is
# what a snapshot tells the phone this machine reads. Keyed by the version AS TEXT: an ordered table
# asked for a whole number answers by position, not by key.
$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }
$script:HordeDecisionsChannelAnswerHighest = 2
$script:HordeDecisionsChannelIdDomain = "horde-relay/decisions/v1 answer id"
# For a test only: the seat and the clock the bell's turn is handed (decisions/Notify.ps1). $null, as it
# is everywhere but in a suite, means the real warchief's seat and the real time.
$script:HordeDecisionsChannelBellSeat = $null
$script:HordeDecisionsChannelBellClock = $null
$script:HordeDecisionsChannelBellRoot = ""
# THE RECEIPTS' SIZE (the header, WHAT BECAME OF EACH ANSWER): for each passkey, the newest 64 answerIds
# applied and 16 refused, and the newest 32 missing seqs looked for within 4096 below the highest; at
# most 16 passkeys. About 3 KB at its fullest for one phone, within every page's frame.
$script:HordeDecisionsChannelReceiptsApplied = 64
$script:HordeDecisionsChannelReceiptsRefused = 16
$script:HordeDecisionsChannelReceiptsMissing = 32
$script:HordeDecisionsChannelReceiptsLookBack = 4096
$script:HordeDecisionsChannelReceiptsStreams = 16

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
    # snapshot; number; wordingVersion; text; part } - part the letter of the one part answered (a
    # version 2 body), or "" for an answer to the whole question (version 1). Never throws for the body:
    # it was signed by the founder's passkey, but the PWA that wrote it is code, and code has bugs.
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
    # THE VERSION FIRST, THEN EXACTLY THAT VERSION'S MEMBERS (header, IN): a version this machine does not
    # read is refused by its number, and a member that belongs to another version is refused as added.
    $version = 0
    if ($null -ne $a.PSObject.Properties["v"] -and ($a.v -is [int] -or $a.v -is [long]) -and $script:HordeDecisionsChannelAnswerVersions.Contains("" + $a.v)) { $version = [int]$a.v }
    if ($version -eq 0) { $fail.reason = ("the answer is not a version this machine reads (" + (@($script:HordeDecisionsChannelAnswerVersions.Keys) -join ", ") + ")"); return $fail }
    $members = @($script:HordeDecisionsChannelAnswerMembers) + @($script:HordeDecisionsChannelAnswerVersions["" + $version])
    if ((@($names | Sort-Object) -join ",") -cne (@($members | Sort-Object) -join ",")) { $fail.reason = ("the answer's members are " + ($names -join ", ") + ", not " + ($members -join ", ")); return $fail }
    if ($a.answerId -isnot [string] -or $a.answerId -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the answer's answerId is not 32 lower-case hex"; return $fail }
    if ($a.machine -isnot [string] -or $a.machine -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the answer's machine is not a key id"; return $fail }
    if ($a.snapshot -isnot [string] -or $a.snapshot.Length -gt 160) { $fail.reason = "the answer's snapshot is not an envelope's replay key"; return $fail }
    if (-not (Test-HordeDecisionCount -Value $a.number -Most (Get-HordeDecisionMaxNumber))) { $fail.reason = "the answer's number is not a question number"; return $fail }
    if (-not (Test-HordeDecisionCount -Value $a.wordingVersion -Most (Get-HordeDecisionMaxNumber))) { $fail.reason = "the answer's wordingVersion is not a wording"; return $fail }
    if ($a.text -isnot [string]) { $fail.reason = "the answer's text is not text"; return $fail }
    $part = ""
    if ($version -ge 2) {
        if ($a.part -isnot [string] -or $a.part -cnotmatch '\A[a-z]\z') { $fail.reason = "the answer's part is not one lower-case letter"; return $fail }
        $part = [string]$a.part
    }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ answerId = $a.answerId; machine = $a.machine; snapshot = $a.snapshot; number = [int]$a.number; wordingVersion = [int]$a.wordingVersion; text = [string]$a.text; part = $part } }
}

function Invoke-HordeDecisionsChannelAccept {
    # One opened answer into the decisions list (IN, in the header), and what became of it into the
    # receipts' ledger by its answerId (WHAT BECAME OF EACH ANSWER). { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeDecisionsChannelAnswer -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    $out = Invoke-HordeDecisionsChannelApply -Context $Context -Item $Item -Answer $r
    # A ledger that cannot be kept costs the phone its word "applied" for this answer, never the answer:
    # it is in the list, and the Tick says the ledger's trouble.
    $null = Add-HordeDecisionsChannelReceipt -Context $Context -From $Item.from -AnswerId $r.value.answerId -Outcome $out.outcome
    return $out
}

function Invoke-HordeDecisionsChannelApply {
    # The answer -Answer (Read-HordeDecisionsChannelAnswer's, ok) into the decisions list. { outcome; reason }.
    param($Context, $Item, $Answer)
    $r = $Answer
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
    # THE PART ANSWERED goes on as the request's own member: the list keeps it as the record of that
    # part, signed and proven like any phone answer (the evidence and signedBy above are every answer's).
    if ($r.value.part -cne "") { $request["part"] = $r.value.part }
    $a = Invoke-HordeDecision -Operation "say" -Request $request -Root $Context.decisionsRoot
    if ($a.state -ceq "unknown") { return [pscustomobject]@{ outcome = "retry"; reason = ("the decisions list could not take it now: " + $a.reason) } }
    if ($a.state -ceq "absent") { return [pscustomobject]@{ outcome = "refused"; reason = ("the decisions list refused it: " + $a.reason) } }
    if ($a.value.outcome -ceq "refused") { return [pscustomobject]@{ outcome = "refused"; reason = ("the decisions list refused it: " + (@($a.value.findings) -join "; ")) } }
    return [pscustomobject]@{ outcome = "done"; reason = ("question " + $r.value.number + $(if ($r.value.part -cne "") { " part (" + $r.value.part + ")" } else { "" }) + ": the founder's answer is record " + $a.value.sequence + " (" + $a.value.outcome + ")") }
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

function Test-HordeDecisionsChannelGlance {
    # THE GLANCE (channels/Port.ps1, Glance): has the list of the store's record names changed since the
    # snapshot Tick last looked? $true then, and the runner runs the Tick now instead of when its watch
    # of the mailbox ends - so the warchief's reply under a question, or a new question, is on the
    # founder's phone in about a second and not in up to a minute.
    #   - THE NAMES ARE LISTED, NOTHING IS OPENED (about 1 ms for a store of 30 questions, measured
    #     2026-10-13; the fingerprint the Tick itself asks by, WHAT CHANGED IS ASKED CHEAPLY in the header), and the trust store is not
    #     read: of the Tick's fingerprint - the names, a bar, the phone keys' ids - only what is before
    #     the bar is compared. So a phone key trusted since is NOT seen here, and waits for the turn's own
    #     Tick as it always did; a key arrives through the mailbox, which ends the watch at once anyway.
    #   - NO, UNTIL THE TICK HAS LOOKED ONCE (no fingerprint yet, or no phone to send to), and NO WHILE
    #     AN ENVELOPE IS RECORDED AND WAITING: the relay would not take it, and putting it again is the
    #     turn's Tick's, after the runner's backoff.
    #   - NO WHEN THE STORE CANNOT BE LISTED: the turn's Tick says why, once a turn.
    param($Context)
    if (-not $Context.state.ContainsKey("decisions")) { return $false }
    $mine = $Context.state["decisions"]
    if (@($mine.pending).Count -ne 0) { return $false }
    $last = "$($mine.fingerprint)"
    $bar = $last.LastIndexOf("|")
    if ($bar -lt 0) { return $false }
    $root = $Context.decisionsRoot
    if ($root -ceq "") { $root = Get-HordeDecisionStoreRoot }
    $names = Get-HordeDecisionsChannelFingerprint -Root $root -PhoneKeyIds @()
    if ($names -ceq "") { return $false }
    return ($names -cne $last.Substring(0, $bar + 1))
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

function Get-HordeDecisionsChannelStatePath {
    # Where the channel keeps what must survive a restart (the header, EVERY OTHER PAGE KEEPS FROM...).
    param($Context)
    $homeDir = $Context.hordeHome
    if ($homeDir -ceq "") { $homeDir = Get-HordeHome }
    return [System.IO.Path]::Combine($homeDir, "relay", "decisions", "state.json")
}

function Read-HordeDecisionsChannelWhole {
    # The first seq of the last snapshot the relay wholly took from THIS machine's key, or 0 for no
    # memory: no file, one that does not read exactly, or one written under another key. Never throws:
    # no memory only costs the trim the other pages would have asked for.
    param($Context)
    try {
        $path = Get-HordeDecisionsChannelStatePath -Context $Context
        if (-not [System.IO.File]::Exists($path)) { return [long]0 }
        $m = [regex]::Match([System.IO.File]::ReadAllText($path), '\A\{"v":1,"machine":"([0-9a-f]{32})","whole":([1-9][0-9]{0,15})\}\s*\z')
        if ($m.Success -and $m.Groups[1].Value -ceq $Context.signKeyId) { return [long]$m.Groups[2].Value }
    } catch { }
    return [long]0
}

function Write-HordeDecisionsChannelWhole {
    # Keep -Whole for the next run: written beside itself, then moved over the old one in one step
    # (core/FileAtomic.ps1). "" when kept, else why not - said once by the Tick, and never a failure.
    param($Context, [long]$Whole)
    try {
        $path = Get-HordeDecisionsChannelStatePath -Context $Context
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        $temp = $path + "." + $PID + ".tmp"
        [System.IO.File]::WriteAllText($temp, ('{"v":1,"machine":"' + $Context.signKeyId + '","whole":' + $Whole + '}'), [System.Text.Encoding]::ASCII)
        Move-HordeFileAtomic -From $temp -To $path
        return ""
    } catch { return ("" + $_.Exception.Message) }
}

# --- RECEIPTS (the header, WHAT BECAME OF EACH ANSWER) ---

function Get-HordeDecisionsChannelReceiptsPath {
    # Where the ledger of what Accept did with each answer is kept across a restart.
    param($Context)
    $homeDir = $Context.hordeHome
    if ($homeDir -ceq "") { $homeDir = Get-HordeHome }
    return [System.IO.Path]::Combine($homeDir, "relay", "decisions", "receipts.json")
}

function Read-HordeDecisionsChannelLedgerFile {
    # The ledger as it was kept: a table from -> { applied; refused }, each an ArrayList of answerIds,
    # oldest first. Empty for no file, or one that does not read exactly as written below: no ledger
    # costs the phone its "applied" for answers it has not yet seen confirmed, which then say
    # "received by PC" until they show in the list - never a wrong state.
    param($Context)
    $out = @{}
    try {
        $path = Get-HordeDecisionsChannelReceiptsPath -Context $Context
        if (-not [System.IO.File]::Exists($path)) { return $out }
        $j = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($path))
        if ($null -eq $j -or $j.v -ne 1) { return @{} }
        foreach ($s in @($j.streams)) {
            if ("$($s.from)" -cnotmatch '\A[0-9a-f]{32}\z') { return @{} }
            $entry = @{ applied = (New-Object System.Collections.ArrayList); refused = (New-Object System.Collections.ArrayList) }
            foreach ($list in @("applied", "refused")) {
                foreach ($id in @($s.$list)) {
                    if ("$id" -cnotmatch '\A[0-9a-f]{32}\z') { return @{} }
                    [void]$entry[$list].Add("$id")
                }
            }
            $out["$($s.from)"] = $entry
        }
    } catch { return @{} }
    return $out
}

function Get-HordeDecisionsChannelLedger {
    # The run's ledger, read from its file the first time a run asks.
    param($Context)
    if (-not $Context.state.ContainsKey("decisions-receipts")) {
        $Context.state["decisions-receipts"] = @{ streams = (Read-HordeDecisionsChannelLedgerFile -Context $Context); problem = "" }
    }
    return $Context.state["decisions-receipts"]
}

function ConvertTo-HordeDecisionsChannelIdList {
    # A list of ids as JSON text, written by hand so the text is the same every time it is the same list.
    param($Ids)
    return ("[" + ((@($Ids) | ForEach-Object { '"' + $_ + '"' }) -join ",") + "]")
}

function Add-HordeDecisionsChannelReceipt {
    # What Accept did with the answer -AnswerId from -From, into the ledger and its file: done is
    # applied, refused is refused, retry is nothing (the journal already says it is received). APPLIED
    # WINS: an answerId once applied is never listed refused - the same id sent again with other words
    # is refused by the list (THE FIRST ANSWER WINS), and the phone must still see its first answer
    # applied. Each list keeps its newest (64 applied, 16 refused), so a receipt stays small. "" when
    # kept, else why not; never throws.
    param($Context, [string]$From, [string]$AnswerId, [string]$Outcome)
    if ($Outcome -cne "done" -and $Outcome -cne "refused") { return "" }
    $ledger = Get-HordeDecisionsChannelLedger -Context $Context
    if (-not $ledger.streams.ContainsKey($From)) { $ledger.streams[$From] = @{ applied = (New-Object System.Collections.ArrayList); refused = (New-Object System.Collections.ArrayList) } }
    $mine = $ledger.streams[$From]
    if ($Outcome -ceq "done") {
        if ($mine.applied -ccontains $AnswerId) { return "" }
        [void]$mine.applied.Add($AnswerId)
        while ($mine.applied.Count -gt $script:HordeDecisionsChannelReceiptsApplied) { $mine.applied.RemoveAt(0) }
        if ($mine.refused -ccontains $AnswerId) { $mine.refused.Remove($AnswerId) }
    } else {
        if ($mine.applied -ccontains $AnswerId -or $mine.refused -ccontains $AnswerId) { return "" }
        [void]$mine.refused.Add($AnswerId)
        while ($mine.refused.Count -gt $script:HordeDecisionsChannelReceiptsRefused) { $mine.refused.RemoveAt(0) }
    }
    try {
        $path = Get-HordeDecisionsChannelReceiptsPath -Context $Context
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        $streams = @($ledger.streams.Keys | Sort-Object | ForEach-Object { '{"from":"' + $_ + '","applied":' + (ConvertTo-HordeDecisionsChannelIdList $ledger.streams[$_].applied) + ',"refused":' + (ConvertTo-HordeDecisionsChannelIdList $ledger.streams[$_].refused) + '}' })
        $temp = $path + "." + $PID + ".tmp"
        [System.IO.File]::WriteAllText($temp, ('{"v":1,"streams":[' + ($streams -join ",") + ']}'), [System.Text.Encoding]::ASCII)
        Move-HordeFileAtomic -From $temp -To $path
        $ledger.problem = ""
        return ""
    } catch { $ledger.problem = "" + $_.Exception.Message; return $ledger.problem }
}

function Get-HordeDecisionsChannelReceipts {
    # The receipts member of the snapshot (the header, WHAT BECAME OF EACH ANSWER), as JSON text:
    #   [{"from":<passkey key id>,"through":<highest seq journaled>,"missing":[<seqs>],"applied":[<ids>],"refused":[<ids>]}]
    # one for each founder passkey that has sent this machine an answer. { text; problem }: problem is a
    # stream the journal could not list, which is left out and said by the Tick. NAMES ARE LISTED, ONE
    # RECORD IS READ: the journal's own stream listing, as every verdict uses it.
    param($Context)
    $ledger = Get-HordeDecisionsChannelLedger -Context $Context
    $root = Get-HordeRelayJournalRoot -HordeHome $Context.hordeHome
    $inDir = [System.IO.Path]::Combine($root, "in")
    $froms = @{}
    foreach ($k in @($ledger.streams.Keys)) { $froms[$k] = $true }
    try {
        if ([System.IO.Directory]::Exists($inDir)) {
            foreach ($d in @([System.IO.Directory]::GetDirectories($inDir))) {
                $n = [System.IO.Path]::GetFileName($d)
                if ($n -cmatch '\As-([0-9a-f]{32})\z' -and [System.IO.Directory]::Exists((Get-HordeRelayJournalStreamDir -Root $root -Direction "in" -From $Matches[1] -Channel "decisions"))) { $froms[$Matches[1]] = $true }
            }
        }
    } catch { return [pscustomobject]@{ text = "[]"; problem = ("the journal's received streams could not be listed: " + $_.Exception.Message) } }
    $parts = New-Object System.Collections.ArrayList
    $problem = ""
    foreach ($from in @($froms.Keys | Sort-Object | Select-Object -First $script:HordeDecisionsChannelReceiptsStreams)) {
        $st = Get-HordeRelayJournalStream -Dir (Get-HordeRelayJournalStreamDir -Root $root -Direction "in" -From $from -Channel "decisions") -Direction "in" -From $from -Channel "decisions"
        if (-not $st.ok) { $problem = $st.reason; continue }
        $through = [long][System.Math]::Max([long]0, [long]$st.last)
        # THE MISSING: seqs below the highest that the journal never recorded - a hole the next envelope
        # of that phone showed (relay/Journal.ps1, gapBefore), and that it now never will take (out of
        # order). The newest of them, looked for no further back than the window below.
        $missing = New-Object System.Collections.ArrayList
        $lowest = [long][System.Math]::Max([long]1, $through - $script:HordeDecisionsChannelReceiptsLookBack)
        for ($s = $through - 1; $s -ge $lowest -and $missing.Count -lt $script:HordeDecisionsChannelReceiptsMissing; $s--) {
            if (-not $st.seqs.ContainsKey("" + $s)) { [void]$missing.Add($s) }
        }
        [void]$missing.Reverse()
        $applied = @(); $refused = @()
        if ($ledger.streams.ContainsKey($from)) { $applied = @($ledger.streams[$from].applied); $refused = @($ledger.streams[$from].refused) }
        [void]$parts.Add('{"from":"' + $from + '","through":' + $through + ',"missing":[' + (@($missing) -join ",") + '],"applied":' + (ConvertTo-HordeDecisionsChannelIdList $applied) + ',"refused":' + (ConvertTo-HordeDecisionsChannelIdList $refused) + '}')
    }
    return [pscustomobject]@{ text = ("[" + (@($parts) -join ",") + "]"); problem = $problem }
}

function New-HordeDecisionsChannelPages {
    # The snapshot as page bodies (OUT, in the header): { hash; bodies; shown; withheld }. -Budget is the
    # largest body one page may have. -OnePage: the one page sent first into a full mailbox (the header,
    # A FULL MAILBOX IS EMPTIED BY ONE PAGE SENT FIRST) - the questions that fit one page, and every
    # other one withheld by number.
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Machine, [Parameter(Mandatory = $true)]$List, [Parameter(Mandatory = $true)][long]$Budget, [switch]$OnePage, [string]$Receipts = "[]")
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
    # "answers": the highest version of answer this machine reads (header, IN). A member a phone that
    # does not know it leaves alone; a phone that does sends a part's answer as that version.
    $tail = ',"counts":' + (ConvertTo-Json -InputObject $List.counts -Compress) + ',"unreadable":' + @($List.unreadable).Count + ',"notUnderstood":' + @($List.notUnderstood).Count + ',"answers":' + $script:HordeDecisionsChannelAnswerHighest + ',"receipts":' + $Receipts + '}'
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
    if ($OnePage) {
        # In the list's order, as a page is filled below; from the first that does not fit, every one
        # is withheld - never one from further down in place of it. The reason is within the 160 bytes
        # the frame counts for each withheld question.
        $onOne = New-Object System.Collections.ArrayList
        $usedOne = $frameBytes
        $cut = $false
        foreach ($s in $fitting) {
            if (-not $cut -and ($onOne.Count -eq 0 -or $usedOne + $s.bytes + 1 -le $Budget)) { [void]$onOne.Add($s); $usedOne += $s.bytes + 1; continue }
            $cut = $true
            [void]$withheld.Add([ordered]@{ number = $s.number; reason = "it is in the snapshot that follows: this one page was sent first, to make room in the phone's full mailbox" })
        }
        $fitting = $onOne
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
        # The last page of a snapshot says to keep from that snapshot's own first page; every other
        # page, from the last snapshot the relay wholly took - or nothing, with no such memory or one
        # that names a seq past the page's own (the header, EVERY OTHER PAGE KEEPS FROM...).
        $isLast = ($null -ne $p.PSObject.Properties["keepFrom"])
        $from = [long]$Mine.whole
        if ($from -gt [long]$p.seq) { $from = [long]0 }
        if ($isLast) { $from = [long]$p.keepFrom }
        $put = Send-HordeRelayChannelSaved -Context $Context -Saved $p -Mailbox $p.mailbox -KeepFrom $from
        if ($put.state -cne "known") {
            # REFUSED AS FULL, AND NOT THE LAST PAGE: the one case one page sent first can mend (the header).
            $status = $put.PSObject.Properties["status"]
            $Mine.stuckFull = (-not $isLast -and $null -ne $status -and [int]$status.Value -eq 507)
            return $put.reason
        }
        $Mine.pending.RemoveAt(0)
        if ($isLast) {
            # A SNAPSHOT IS WHOLE AT THE RELAY: remembered here, and for the next run.
            $Mine.whole = [long]$p.keepFrom
            $Mine.wholeProblem = Write-HordeDecisionsChannelWhole -Context $Context -Whole $Mine.whole
        }
    }
    $Mine.stuckFull = $false
    return ""
}

function Test-HordeDecisionsChannelOnePageFirst {
    # Is this the moment to let the waiting pages go and send one page first (the header, A FULL MAILBOX
    # IS EMPTIED BY ONE PAGE SENT FIRST)? $true, with the waiting pages let go, when a page that was
    # not the last was just refused as full and no such page has been sent yet in this run.
    param($Mine)
    if (-not $Mine.stuckFull -or $Mine.onePageSent) { return $false }
    $Mine.pending.Clear()
    $Mine.stuckFull = $false
    $Mine.onePageNext = $true
    return $true
}

function Invoke-HordeDecisionsChannelBell {
    # THE BELL (the founder's bug of 2026-10-12): an answer from the phone is written to the store by this
    # channel's Accept, and with the decisions window closed nobody was running notify, so the warchief
    # was never told. Each Tick therefore turns the bell once - decisions/Notify.ps1's own pass, through
    # Invoke-HordeDecisionNotifyTurn, which stands aside while a notify loop (the window's) holds the
    # home's bell. { lines; againMs }: a line when the bell has something new to say, and how soon the run
    # should turn again for the bell's sake (the quiet period's end), so a watch is not waited out first.
    # Never fails the Tick: a bell that cannot ring says so and the snapshot still goes.
    param($Context)
    if (-not $Context.state.ContainsKey("decisions-bell")) { $Context.state["decisions-bell"] = @{} }
    # The store this run reads and writes, for the bell's reading of the inbox: a script block cannot
    # carry a local, so it is kept where the block finds it.
    $script:HordeDecisionsChannelBellRoot = $Context.decisionsRoot
    $inbox = { return (Invoke-HordeDecision -Operation "inbox" -Request @{ actor = "warchief" } -Root $script:HordeDecisionsChannelBellRoot) }
    try {
        $turn = Invoke-HordeDecisionNotifyTurn -Memory $Context.state["decisions-bell"] -HordeHome $Context.hordeHome -StoreRoot $Context.decisionsRoot -Inbox $inbox -Seat $script:HordeDecisionsChannelBellSeat -Clock $script:HordeDecisionsChannelBellClock
    } catch { return [pscustomobject]@{ lines = @("the founder's answers could not be rung for: " + $_.Exception.Message); againMs = 0 } }
    $lines = @()
    if ("$($turn.said)" -cne "") { $lines = @("notify: " + $turn.said) }
    return [pscustomobject]@{ lines = $lines; againMs = [int]$turn.againMs }
}

function Invoke-HordeDecisionsChannelTick {
    # OUT, in the header, then THE BELL: { lines; failed; againMs }.
    param($Context)
    $out = Invoke-HordeDecisionsChannelSnapshotTick -Context $Context
    $bell = Invoke-HordeDecisionsChannelBell -Context $Context
    return [pscustomobject]@{ lines = @(@($out.lines) + @($bell.lines)); failed = [bool]$out.failed; againMs = $bell.againMs }
}

function Invoke-HordeDecisionsChannelSnapshotTick {
    # OUT, in the header: { lines; failed }.
    param($Context)
    if (-not $Context.state.ContainsKey("decisions")) { $Context.state["decisions"] = @{ fingerprint = $null; sent = ""; pending = (New-Object System.Collections.ArrayList) } }
    $mine = $Context.state["decisions"]
    # What must survive a restart, read once a run; and what this run knows of a full mailbox.
    if (-not $mine.ContainsKey("whole")) { $mine.whole = (Read-HordeDecisionsChannelWhole -Context $Context); $mine.wholeProblem = ""; $mine.stuckFull = $false; $mine.onePageNext = $false; $mine.onePageSent = $false }
    $said = New-Object System.Collections.ArrayList
    # What was recorded and not taken, first: the same envelopes, never new ones.
    if ($mine.pending.Count -gt 0) {
        $waiting = $mine.pending.Count
        $why = Send-HordeDecisionsChannelPending -Context $Context -Mine $mine
        if ($why -cne "") {
            if (-not (Test-HordeDecisionsChannelOnePageFirst -Mine $mine)) { return [pscustomobject]@{ lines = @("snapshot not delivered yet (" + $mine.pending.Count + " envelope(s) recorded and waiting): " + $why); failed = $true } }
            [void]$said.Add("the phone's mailbox is full and would not take a page of the snapshot (" + $waiting + " waiting): they are let go, and one page is sent first to make room")
        }
        elseif ("$($mine.fingerprint)" -cne "one page") { $mine.onePageSent = $false }
    }
    $onePage = [bool]$mine.onePageNext
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
    # THE RECEIPTS ARE ASKED EVERY LOOK, as cheaply as the names (the header, WHAT BECAME OF EACH ANSWER):
    # an answer refused, or a hole in a phone's stream, changes them and no record name.
    $receipts = Get-HordeDecisionsChannelReceipts -Context $Context
    $ledger = Get-HordeDecisionsChannelLedger -Context $Context
    foreach ($trouble in @($receipts.problem, $ledger.problem)) { if ("$trouble" -cne "" -and "$trouble" -cne "$($mine.receiptsProblem)") { [void]$said.Add("the receipts of the founder's answers are short: " + $trouble); $mine.receiptsProblem = "$trouble" } }
    if ("$($receipts.problem)$($ledger.problem)" -ceq "") { $mine.receiptsProblem = "" }
    if (-not $onePage -and $print -cne "" -and $print -ceq $mine.fingerprint -and $receipts.text -ceq "$($mine.receipts)") { return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false } }
    $list = Invoke-HordeDecision -Operation "list" -Request @{ state = "open"; messages = $true } -Root $Context.decisionsRoot
    if ($list.state -cne "known" -or $list.value.outcome -cne "done") { return [pscustomobject]@{ lines = @("no snapshot: the decisions list could not be read (" + $(if ($list.state -ceq "known") { $list.value.reason } else { $list.reason }) + ")"); failed = $true } }
    $budget = Get-HordeRelayChannelBodyBudget -Context $Context -Recipients $keys.Count
    $pages = New-HordeDecisionsChannelPages -Horde $Context.horde -Machine $Context.signKeyId -List $list.value -Budget $budget -OnePage:$onePage -Receipts $receipts.text
    # THE SAME SNAPSHOT FOR THE SAME PHONES is not sent again; the same snapshot for ANOTHER SET OF
    # PHONES is. What was sent is remembered as its hash and the keys it was sealed to: until
    # 2026-10-13 it was the hash alone, so a phone paired while the list stood still was sent nothing
    # until some record changed - and nothing already in the mailbox was sealed to it.
    $sentAs = $pages.hash + "|" + (@($keys | ForEach-Object { $_.agreeKeyId }) -join ",")
    if (-not $onePage -and $sentAs -ceq $mine.sent) { $mine.fingerprint = $print; $mine.receipts = $receipts.text; return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false } }
    $mailbox = New-HordeRelayMailbox -Horde $Context.horde -Reader "phone"
    $recipients = @($keys | ForEach-Object { , ([byte[]]$_.public) })
    $keysSent = New-Object System.Collections.ArrayList
    $firstSeq = [long]0
    $lastPage = $null
    foreach ($body in @($pages.bodies)) {
        $saved = Save-HordeRelayChannelEnvelope -Context $Context -Channel "decisions" -Kind "snapshot" -Body ([byte[]]$body) -Recipients $recipients
        if ($saved.state -cne "known") { return [pscustomobject]@{ lines = @("no snapshot: " + $saved.reason); failed = $true } }
        $saved.value | Add-Member -NotePropertyName "mailbox" -NotePropertyValue $mailbox
        [void]$mine.pending.Add($saved.value)
        [void]$keysSent.Add($saved.value.key)
        if ($firstSeq -eq 0) { $firstSeq = [long]$saved.value.seq }
        $lastPage = $saved.value
    }
    # THE LAST PAGE, AND ONLY ONCE EVERY PAGE IS RECORDED, is told what to keep from: this snapshot's
    # first page (the header, THE SNAPSHOT BEFORE IS DEAD WEIGHT). A snapshot whose pages could not all
    # be recorded returned above, with no page of it saying anything.
    if ($null -ne $lastPage) { $lastPage | Add-Member -NotePropertyName "keepFrom" -NotePropertyValue $firstSeq }
    # Every page is recorded: this snapshot is the one sent, whatever the relay does next.
    $mine.sent = $sentAs
    $mine.fingerprint = $print
    $mine.receipts = $receipts.text
    # THE ONE PAGE IS RECORDED: it is not what the list is, so the fingerprint is one no look can match,
    # and the look after it sends the whole snapshot. And it is sent once a run (the header).
    if ($onePage) { $mine.fingerprint = "one page"; $mine.onePageNext = $false; $mine.onePageSent = $true }
    $what = "snapshot of " + $pages.shown + " open question(s)" + $(if ($pages.withheld -gt 0) { ", " + $pages.withheld + " withheld" } else { "" }) + " in " + @($pages.bodies).Count + " page(s) for " + $keys.Count + " phone key(s), as " + ($keysSent -join ", ")
    $why = Send-HordeDecisionsChannelPending -Context $Context -Mine $mine
    if ($why -cne "") {
        if (-not (Test-HordeDecisionsChannelOnePageFirst -Mine $mine)) { return [pscustomobject]@{ lines = @(@($said.ToArray()) + @($what + " recorded; not delivered yet: " + $why)); failed = $true } }
        # A page of it that was not the last was refused as full: one page first, in this same look.
        [void]$said.Add($what + " recorded; the phone's mailbox is full and would not take a page of it: its pages are let go, and one page is sent first to make room")
        $first = Invoke-HordeDecisionsChannelSnapshotTick -Context $Context
        return [pscustomobject]@{ lines = @(@($said.ToArray()) + @($first.lines)); failed = [bool]$first.failed }
    }
    [void]$said.Add($what + " sent")
    if ($mine.wholeProblem -cne "") { [void]$said.Add("what the relay last wholly took could not be kept for the next run (" + $mine.wholeProblem + "): it costs that run one trim, nothing else"); $mine.wholeProblem = "" }
    if ($onePage) {
        # THE ROOM IS MADE: the whole snapshot now, in the same look, and it replaces the one page.
        $whole = Invoke-HordeDecisionsChannelSnapshotTick -Context $Context
        return [pscustomobject]@{ lines = @(@($said.ToArray()) + @($whole.lines)); failed = [bool]$whole.failed }
    }
    if (@($pages.bodies).Count -gt 1) { $mine.onePageSent = $false }
    return [pscustomobject]@{ lines = @($said.ToArray()); failed = $false }
}

$null = Register-HordeRelayChannel -Folder $script:HordeDecisionsChannelFolder -Name "decisions" -Kinds @("answer") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeDecisionsChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeDecisionsChannelTick -Context $Context) } `
    -Glance { param($Context) return (Test-HordeDecisionsChannelGlance -Context $Context) }
