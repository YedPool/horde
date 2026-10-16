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
# local session could say. What the record holds that a local caller cannot make is a pointer into the
# relay journal: evidence, the SHA-256 of the journal record that holds the envelope whole, as it was
# signed (relay/Journal.ps1, EVIDENCE). Test-HordeDecisionsChannelPasskeyAnswer starts from that hash and
# from nothing else the request asserts, and says yes only when ALL of these hold, each read from this
# machine's own stores at the time of asking:
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
# What a local caller can still do is what the journal's own honest limit says (relay/Journal.ps1, THE
# HONEST LIMIT): whoever can write this home's trust store and journal AND sign as a trusted passkey is
# the machine's owner. Nothing here can make a passkey signature, so no request, flag or record that a
# session can write passes these checks without one.
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

function Test-HordeDecisionsChannelPasskeyAnswer {
    # Did the founder's passkey sign exactly these words, as an answer to question -Number, on this
    # machine (the header, A PASSKEY ANSWER IS PROVEN AGAIN)? { ok; reason; keyId; signedAt }: ok only when
    # every check holds; reason, when it is not, says the first that failed in words; signedAt is the
    # envelope's own signed time (ms). Never throws: a check that cannot be made is a no.
    # -Id is the request id the record has (or the request carries); -WordingVersion 0 means not stated.
    # -HordeHome is the home whose journal, trust store and identity are read; "" is Horde's own.
    param([string]$Id, [int]$Number, [AllowEmptyString()][string]$Text, [string]$Part = "", [int]$WordingVersion = 0,
        [string]$Evidence = "", [string]$SignedBy = "", [string]$HordeHome = "", $Now = $null)
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
        if ($opening.state -cne "known") { return (& $no ("this machine's keys cannot be opened to read it: " + $opening.reason)) }
        $keys = $opening.value.keys
        $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = $found.record.meta.key; fresh = $true; why = ""; gapBefore = [long]0; direction = "in"; resumed = $true }) -ObservedAt ([datetime]::UtcNow)
        $opened = Unprotect-HordeRelayEnvelope -Envelope $env.value -Senders @{ $SignedBy = $sender.value } -RecipientKeys $keys -Replay $verdict -Channel "decisions" -Kind "answer"
        if (-not $opened.ok) { return (& $no ("its envelope does not verify and open here: " + $opened.reason)) }
        $body = Read-HordeDecisionsChannelAnswer -Body $opened.value
        if (-not $body.ok) { return (& $no ("its envelope holds no answer: " + $body.reason)) }
        $b = $body.value
        $me = Get-HordeRelayMachineIdentity -HordeHome $HordeHome -Now $Now
        if ($me.state -cne "known") { return (& $no ("this machine's identity cannot be read: " + $me.reason)) }
        if ($b.machine -cne $me.value.sign.keyId) { return (& $no "the signed answer is for another machine") }
        if ($b.number -ne $Number) { return (& $no ("the signed answer is to question " + $b.number + ", not " + $Number)) }
        if ($b.text -cne $Text) { return (& $no "the signed answer says other words") }
        if ($b.part -cne $Part) { return (& $no "the signed answer is to another part") }
        if ($b.wordingVersion -ne $WordingVersion) { return (& $no ("the signed answer was given to wording " + $b.wordingVersion + ", not " + $WordingVersion)) }
        if ((Get-HordeDecisionsChannelAnswerId -From $SignedBy -AnswerId $b.answerId) -cne $Id) { return (& $no "its id is not the one made from the signed answer") }
        return [pscustomobject]@{ ok = $true; reason = ""; keyId = $SignedBy; signedAt = [long]$env.value.header.ts }
    } catch {
        return (& $no ("it could not be checked: " + $_.Exception.Message))
    } finally {
        if ($null -ne $keys) { foreach ($k in @($keys.Values)) { try { $k.Dispose() } catch { } } }
    }
}
