# channels/decisions/Answer.ps1 - the founder's answer from the phone as the decisions channel reads it:
# its body, the request id made from it, and the one check that a record of the list holds an answer his
# passkey signed. channels/decisions/Channel.ps1 takes answers in with the first two; decisions/Operations.ps1
# asks the third, and loads this file for it, so that the list itself can refuse a needs-passkey answer
# without a proof and `horde decisions authorized` can tell a production wrapper whether one stands.
# This file loads no part of the list (decisions/Operations.ps1 loads it), so neither can load the other
# in a circle.
#
# A PASSKEY ANSWER IS PROVEN AGAIN FROM ITS EVIDENCE, NEVER TAKEN FROM A FLAG (audit of 2026-10-16, item 17:
# the passkey rule for production actions was enforced only on the phone path). The list runs in the
# caller's process, so anything a request says about itself - "signed by a passkey", proof webauthn - any
# caller could say. What the record holds instead is a pointer into the relay journal: evidence, the
# SHA-256 of the journal record that holds the envelope whole, as it was signed (relay/Journal.ps1,
# EVIDENCE). Test-HordeDecisionsChannelPasskeyAnswer starts from that hash and from nothing else the
# request asserts, and says yes only when ALL of these hold, each read from this machine's own stores at
# the time of asking:
#   1. the signer the record names (signedBy) is a device trusted NOW - not pending, expired or revoked
#      (relay/Trust.ps1, Find-HordeRelayTrustedSender): a revoked phone's old answers stop counting;
#   2. the journal of this home holds, in that signer's decisions stream, a record whose hash is the
#      evidence, and the record is an answer;
#   3. its envelope is signed by a passkey assertion (webauthn.get), not by an unlocked session's key nor
#      by a machine - only his face or PIN at that moment answers a needs-passkey question (relay/Session.ps1);
#   4. the assertion verifies against that device's key, its relying party and origins, with user
#      verification (relay/Envelope.ps1's own verifier, through Unprotect-HordeRelayEnvelope);
#   5. the body, opened with this machine's own agreement keys, is an answer for THIS machine, and says
#      exactly what the record says: the same question, the same words, the same part and the same
#      wording - and the record's id is the one the channel derives from the signer and that answer's
#      answerId. So a real passkey answer to one question cannot be pointed at from a record of another,
#      or from other words.
# And, asked by `horde decisions authorized` (-LaterParts): 6. no LATER answer of his to the same question
# and part (to any part, when the whole question is asked) is in the journal (Find-HordeDecisionsChannelLaterAnswer). The journal, not the list, says
# which of his signed answers is the newest, so a "no" record deleted from the list, or edited so that it
# reads as something else, does not bring an older "yes" back.
# WHAT THIS STOPS, AND WHAT IT DOES NOT (security review of PR 324, M1 and M2). It stops every honest and
# every mistaken way an answer reaches the list without his passkey: words recorded from chat, the
# window, the command line, a phone answer signed by an unlocked session, a request or a channel item
# that only CLAIMS a passkey, a real answer pointed at the wrong question, words or wording, a replay of
# an old answer, and a revoked phone. It is NOT a defence against a hostile process running as this
# Windows user. The trust store, the journal and the decisions store are plain files that user can write
# (relay/Journal.ps1, THE HONEST LIMIT, says the same of the journal): such a process can pair a passkey
# of its own in software, sign an envelope with it, journal it and write the record, and every check
# here passes. A real defence needs an anchor outside this PC, which is a separate design.
#
# THE ID OF AN ANSWER (channels/decisions/Channel.ps1, IN, has the whole rule):
#   id = the first 16 bytes of SHA-256("horde-relay/decisions/v1 answer id" LF <sender key id> LF <answerId>)
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "decisions\Rules.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "relay\Trust.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "relay\Journal.ps1")

$script:HordeDecisionsChannelAnswerMembers = @("v", "answerId", "machine", "snapshot", "number", "wordingVersion", "text")
# THE ANSWER'S VERSIONS, each with the one member it adds to those above (channels/decisions/Channel.ps1,
# IN). Keyed by the version AS TEXT: an ordered table asked for a whole number answers by position, not by key.
$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }
$script:HordeDecisionsChannelIdDomain = "horde-relay/decisions/v1 answer id"

function Get-HordeDecisionsChannelAnswerId {
    # The decisions request id of one answer (the header): 32 lower-case hex. -Domain: another kind's own
    # (a change of rank's), so that two kinds can never share a request id.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$AnswerId, [string]$Domain = $script:HordeDecisionsChannelIdDomain)
    $h = Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text ($Domain + "`n" + $From + "`n" + $AnswerId))
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
    try { $a = ConvertFrom-HordeJson $text } catch { $fail.reason = "the answer is not JSON"; return $fail }
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

function Find-HordeDecisionsChannelJournalAnswer {
    # The journal record of -From's decisions stream whose evidence (the SHA-256 of the whole record) is
    # -Evidence: { ok; reason; record } - record Read-HordeRelayJournalRecord's, ok. Newest first: an
    # answer is checked soon after it lands, and the streams are short.
    param([string]$HordeHome, [string]$From, [string]$Evidence)
    $none = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why; record = $null } }
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (& $none ("the relay journal cannot be read: " + $ctx.reason)) }
    $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "in" -From $From -Channel "decisions"
    $st = Get-HordeRelayJournalStream -Dir $dir -Direction "in" -From $From -Channel "decisions"
    if (-not $st.ok) { return (& $none ("the journal's stream of that passkey cannot be read: " + $st.reason)) }
    # Sorted as numbers, by [Array]::Sort (relay/Journal.ps1 does the same).
    $nums = [long[]]@($st.seqs.Keys | ForEach-Object { [long]$_ })
    [System.Array]::Sort($nums)
    [System.Array]::Reverse($nums)
    foreach ($n in $nums) {
        $r = Read-HordeRelayJournalRecord -Dir $dir -Direction "in" -From $From -Channel "decisions" -Seq $n
        if (-not $r.ok) { return (& $none ("the journal's stream of that passkey is damaged: " + $r.reason)) }
        if ((ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))) -ceq $Evidence) {
            return [pscustomobject]@{ ok = $true; reason = ""; record = $r }
        }
    }
    return (& $none "this machine's relay journal holds no envelope from that passkey with that evidence")
}

function Open-HordeDecisionsChannelJournalBody {
    # The body of a journaled envelope, opened with -Keys (this machine's agreement keys), its signature
    # NOT asked again: for Find-HordeDecisionsChannelLaterAnswer only, which can only refuse. Every
    # envelope was verified before the journal took it (relay/Envelope.ps1, step 1); a session's could
    # not be verified again here without the session records, and one this check cannot read must still
    # count. $null when it does not open.
    param([string]$Text, [hashtable]$Keys)
    $read = Read-HordeRelayEnvelope -Text $Text
    if (-not $read.ok) { return $null }
    $e = $read.value
    $mine = $null
    foreach ($r in @($e.recipients)) { if ($Keys.ContainsKey($r.kid)) { $mine = $r; break } }
    if ($null -eq $mine) { return $null }
    $aad = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayEnvelopeDomain -Part "aad") + $e.headerText)
    $info = Get-HordeRelayAsciiBytes -Text (Get-HordeRelayEnvelopeDomain -Part "info")
    $cek = Unprotect-HordeRelayHpke -RecipientKey $Keys[$mine.kid] -Enc $mine.enc -Info $info -Aad $aad -Sealed $mine.key
    if ($null -eq $cek -or $cek.Length -ne 32) { return $null }
    $body = Unprotect-HordeRelayAesGcm -Key $cek -Nonce (ConvertFrom-HordeRelayHex -Text $e.header.nonce) -Aad $aad -Sealed $e.ct
    [System.Array]::Clear($cek, 0, $cek.Length)
    if ($null -eq $body) { return $null }
    return ,([byte[]]$body)
}

function Find-HordeDecisionsChannelLaterAnswer {
    # Is there, in this home's journal, an answer to question -Number - to one of -Parts ("" the whole
    # question), or to any part at all with -AnyPart - that came after the standing answer, other than
    # that same answer sent again (request id -Id)? { ok; reason }: ok when there is none (the header, 6).
    # LATER means signed after it (-After, the envelope's own time) OR recorded by this machine after it
    # (-AfterRecorded, this journal's own clock): a phone whose clock runs behind still signs a later
    # "no" with an earlier time, and the PC's record of when it arrived still says it is later. The
    # phone resends an answer under the time it first signed and the same answerId, so a resend of the
    # standing answer is that answer, by its id. Every received decisions stream is read, whoever sent
    # it, however it was signed and whether that device is trusted now: a "no" from his other phone, by
    # an unlocked session, or from a phone revoked since, is his word too. EVERY DOUBT REFUSES (review of
    # PR 324): a folder the journal never makes, a stream that cannot be read, a damaged record, a later
    # envelope that cannot be opened here, and a later body this machine does not read (a newer phone
    # sends a body version this one does not know) - what it says cannot be known, so it may be his no.
    # NOT READ: a writer's temporary file (writing-*.part). It is an envelope the journal never took -
    # killed before its move, it was never opened and the phone was never told it arrived, so the phone
    # sends it again (relay/Journal.ps1, WRITE-ONCE).
    param([string]$HordeHome, [int]$Number, [string[]]$Parts, [switch]$AnyPart, [long]$After, [long]$AfterRecorded, [string]$Id, [string]$Machine, [hashtable]$Keys)
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why } }
    $again = " To clear it, he answers again on his phone."
    $ctx = Get-HordeRelayJournalContext -HordeHome $HordeHome
    if (-not $ctx.ok) { return (& $no ("the relay journal cannot be read to find a later answer: " + $ctx.reason)) }
    $inDir = [System.IO.Path]::Combine($ctx.root, "in")
    $names = @()
    if ([System.IO.Directory]::Exists($inDir)) { $names = @([System.IO.Directory]::GetDirectories($inDir) | ForEach-Object { [System.IO.Path]::GetFileName($_) }) }
    foreach ($nm in $names) {
        if ($nm -cnotmatch $script:HordeRelayJournalSenderDirPattern) { return (& $no ("the journal's received streams hold " + $nm + ", which the journal never makes")) }
        $from = $Matches[1]
        $dir = Get-HordeRelayJournalStreamDir -Root $ctx.root -Direction "in" -From $from -Channel "decisions"
        $st = Get-HordeRelayJournalStream -Dir $dir -Direction "in" -From $from -Channel "decisions"
        if (-not $st.ok) { return (& $no ("the journal's decisions stream from " + $from + " cannot be read to find a later answer: " + $st.reason)) }
        foreach ($seqText in @($st.seqs.Keys)) {
            $r = Read-HordeRelayJournalRecord -Dir $dir -Direction "in" -From $from -Channel "decisions" -Seq ([long]$seqText)
            if (-not $r.ok) { return (& $no ("the journal's decisions stream from " + $from + " is damaged: " + $r.reason)) }
            if ($r.meta.kind -cne "answer") { continue }
            if ($r.meta.ts -le $After -and $r.meta.recordedAt -le $AfterRecorded) { continue }
            $body = Open-HordeDecisionsChannelJournalBody -Text $r.envelope -Keys $Keys
            if ($null -eq $body) { return (& $no ("a later envelope in the journal (" + $r.meta.key + ") cannot be opened here to see what it answers." + $again)) }
            $a = Read-HordeDecisionsChannelAnswer -Body $body
            if (-not $a.ok) { return (& $no ("a later envelope in the journal (" + $r.meta.key + ") holds an answer this machine does not read (" + $a.reason + "), so it may be his no." + $again)) }
            if ($a.value.machine -cne $Machine -or $a.value.number -ne $Number) { continue }
            if (-not $AnyPart -and @($Parts) -cnotcontains $a.value.part) { continue }
            if ((Get-HordeDecisionsChannelAnswerId -From $from -AnswerId $a.value.answerId) -ceq $Id) { continue }
            return (& $no ("a later answer of his to it is in this machine's relay journal (" + $r.meta.key + "), and the list does not hold it as the standing answer: the list lost it or reads it otherwise, or it came after. Ask him again"))
        }
    }
    return [pscustomobject]@{ ok = $true; reason = "" }
}

function Test-HordeDecisionsChannelPasskeyAnswer {
    # Did the founder's passkey sign exactly these words, as an answer to question -Number, on this
    # machine (the header, A PASSKEY ANSWER IS PROVEN AGAIN)? { ok; reason; keyId; signedAt }: ok only when
    # every check holds; reason, when it is not, says the first that failed in words; signedAt is the
    # envelope's own signed time (ms). Never throws: a check that cannot be made is a no.
    # -Id is the request id the record has (or the request carries); -WordingVersion 0 means not stated.
    # -HordeHome is the home whose journal, trust store and identity are read; "" is Horde's own.
    # -LaterParts: also ask the journal for a later answer to these parts (the header, 6); -LaterAnyPart:
    # to any part or the whole; neither asks not.
    param([string]$Id, [int]$Number, [AllowEmptyString()][string]$Text, [string]$Part = "", [int]$WordingVersion = 0,
        [string]$Evidence = "", [string]$SignedBy = "", [string]$HordeHome = "", $Now = $null, [string[]]$LaterParts = $null, [switch]$LaterAnyPart)
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why; keyId = ""; signedAt = [long]-1 } }
    $keys = $null
    try {
        if ($Evidence -cnotmatch '\A[0-9a-f]{64}\z' -or $SignedBy -cnotmatch '\A[0-9a-f]{32}\z') { return (& $no "it carries no evidence of a passkey signature: only an answer from the phone does") }
        # 1. The signer, trusted NOW.
        $sender = Find-HordeRelayTrustedSender -HordeHome $HordeHome -KeyId $SignedBy -Now $Now
        if ($sender.state -cne "known") { return (& $no ("the passkey it names is not trusted on this machine now (" + $sender.reason + ")")) }
        # 2. The journal record the evidence names.
        $found = Find-HordeDecisionsChannelJournalAnswer -HordeHome $HordeHome -From $SignedBy -Evidence $Evidence
        if (-not $found.ok) { return (& $no $found.reason) }
        # The record's stream is the signer's own (the journal checks a record's sender against its
        # folder), and its kind is asked by Unprotect below.
        $env = Read-HordeRelayEnvelope -Text $found.record.envelope
        if (-not $env.ok) { return (& $no ("the journal record it names holds no envelope: " + $env.reason)) }
        # 3. A fresh passkey assertion, not a session's key nor a machine's (a machine's key signs ES256, and
        # Unprotect below refuses an assertion from a sender that is not a passkey).
        if ("$($env.value.sig.alg)" -cne "webauthn.get") { return (& $no ("it was signed " + $(if ("$($env.value.sig.alg)" -ceq "session") { "by an unlocked session on the phone" } else { "by a machine key" }) + ", not by a fresh passkey")) }
        # 4 and 5. Verified and opened by relay's own code: Unprotect checks the signature again against the
        # sender trusted now, and takes a journal verdict for THIS envelope. The verdict is the record
        # itself - this journal recorded the envelope once (relay/Journal.ps1, FINISHED AND UNFINISHED,
        # makes the same one for a record it hands back) - since what is asked here is what it said, not
        # whether it may be acted on again: the list's own idempotency answers that.
        $opening = Get-HordeRelayOpeningKeys -HordeHome $HordeHome -Now $Now
        if ($opening.state -cne "known") { return (& $no ("this machine's keys cannot be opened to read it: " + $opening.reason + ". Once they open again, or after he answers again on his phone, it can be proven")) }
        $keys = $opening.value.keys
        $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = $found.record.meta.key; fresh = $true; why = ""; gapBefore = [long]0; direction = "in"; resumed = $true }) -ObservedAt ([datetime]::UtcNow)
        $opened = Unprotect-HordeRelayEnvelope -Envelope $env.value -Senders @{ $SignedBy = $sender.value } -RecipientKeys $keys -Replay $verdict -Channel "decisions" -Kind "answer"
        if (-not $opened.ok) { return (& $no ("its envelope does not verify and open here: " + $opened.reason + ". If this machine's keys were rotated since he answered, he answers again on his phone")) }
        $body = Read-HordeDecisionsChannelAnswer -Body $opened.value
        if (-not $body.ok) { return (& $no ("its envelope holds no answer: " + $body.reason)) }
        $b = $body.value
        # This machine's key id comes with its keys (relay/Identity.ps1): one read of the identity.
        if ($b.machine -cne $opening.value.signKeyId) { return (& $no "the signed answer is for another machine") }
        if ($b.number -ne $Number) { return (& $no ("the signed answer is to question " + $b.number + ", not " + $Number)) }
        if ($b.text -cne $Text) { return (& $no "the signed answer says other words") }
        if ($b.part -cne $Part) { return (& $no "the signed answer is to another part") }
        if ($b.wordingVersion -ne $WordingVersion) { return (& $no ("the signed answer was given to wording " + $b.wordingVersion + ", not " + $WordingVersion)) }
        if ((Get-HordeDecisionsChannelAnswerId -From $SignedBy -AnswerId $b.answerId) -cne $Id) { return (& $no "its id is not the one made from the signed answer") }
        if ($null -ne $LaterParts -or $LaterAnyPart) {
            $later = Find-HordeDecisionsChannelLaterAnswer -HordeHome $HordeHome -Number $Number -Parts $LaterParts -AnyPart:$LaterAnyPart -After ([long]$env.value.header.ts) -AfterRecorded ([long]$found.record.meta.recordedAt) -Id $Id -Machine $opening.value.signKeyId -Keys $keys
            if (-not $later.ok) { return (& $no $later.reason) }
        }
        return [pscustomobject]@{ ok = $true; reason = ""; keyId = $SignedBy; signedAt = [long]$env.value.header.ts }
    } catch {
        return (& $no ("it could not be checked: " + $_.Exception.Message))
    } finally {
        if ($null -ne $keys) { foreach ($k in @($keys.Values)) { try { $k.Dispose() } catch { } } }
    }
}
