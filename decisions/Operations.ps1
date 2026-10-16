# decisions/Operations.ps1 - the one list of things that can be done to the decisions list.
#
# THIS IS THE ONLY THING A CALLER USES. The command line calls it today (cli/commands/decisions.ps1); a
# window and a link between machines are meant to call it later, unchanged. So:
#   - PLAIN DATA IN, PLAIN DATA OUT. A request is an object that could be written as JSON, checked
#     against its definition in schema/decision-request.v1 before anything is read or written. What
#     comes back is a core/Tristate.ps1 answer whose value is checked against
#     schema/decision-result.v1 before it is returned.
#   - NOTHING HERE ASSUMES A CONSOLE, a file a person wrote, or a person at all. It prints nothing,
#     prompts for nothing, and reads no file but the store's own records - and, for a question that
#     needs a passkey only, the proof of one (below, A QUESTION THAT NEEDS A PASSKEY).
#   - ONE ENTRY POINT, Invoke-HordeDecision, AND ONE TABLE of operations. A new operation is an entry
#     in $HordeDecisionOperations, its function below, and its definition in the request schema.
#
# WHAT THE ANSWER'S THREE STATES MEAN HERE (schema/decision-result.v1 says it in full):
#   known    the value says what happened: outcome done, replayed (the same id and request were
#            recorded before; nothing was written) or refused (nothing was written; findings says why).
#   absent   the store was read and there is no question of that number.
#   unknown  the store, or the one record asked about, could not be read or written; the reason says.
#            Also: a record was given its place but could not be confirmed on disk. That is never
#            "done" - a caller is told its words are saved only when everything that makes them
#            durable returned success (decisions/Store.ps1) - and the reason says the record is there.
# A refusal is KNOWN on purpose: "I will not" is a fact with reasons, and a caller must never retry it
# as if the store had been unreachable.
#
# HOW A WRITE STAYS CORRECT WITH SEVERAL WRITERS. A write reads every record, works out the list,
# checks the request against that list, and then tries to create the record numbered one past the last
# it read. decisions/Store.ps1 lets exactly one writer create a given number. A writer that loses reads
# the list again - now holding the winner's record - and checks its request AGAIN before trying the
# next number. So every record was checked against the list exactly as it stood before it, and two
# requests that cannot both hold (two closes of one question) cannot both be written. No lock is
# held and none can be left behind by a process that dies.
#
# IDEMPOTENCY. Every write carries an id its caller chose. The id is looked up in the list before the
# request is judged: the same id with the same request is answered from the record already there and
# writes nothing, however often it is sent and whatever has happened to the question since; the same
# id with a different request is refused. A writer that loses the race to another process sending the
# same id finds that record on its next read and replays it, so two deliveries of one request make
# one record. What is compared is a hash of the request as the rules normalised it, not its spelling.
#
# SECRETS ARE LOOKED FOR FIRST, over every text of the request, before the schema check, so that no
# later finding - "the actor is 'x', not one of ..." - can repeat one.
#
# THE CONVERSATION UNDER A QUESTION is two operations and nothing else:
#   say    someone's words under a question, kept verbatim. Who may speak, by what route, and who may
#          record whose words are the rules' closed lists (decisions/Rules.ps1); a caller across a
#          bridge or a link sends the same request the command line does.
#   inbox  what others have said that the actor has not read, under every question, oldest first.
#          IT ONLY READS: it marks nothing and writes nothing, however often it is asked.
#   mark-read  records, as one record of its own, that the actor has read up to a given record.
#          READING AND MARKING ARE TWO OPERATIONS, ON PURPOSE. A caller shows a person the messages
#          an inbox handed it, and only then marks, naming the last one it showed: a message that
#          arrived in between is beyond that record and stays unread, and a caller that dies between
#          the two leaves messages unread that were seen - which shows them again - never messages
#          marked read that nobody saw. There is no "mark everything", and no way to mark and be
#          handed the words in one call. Marking is idempotent: up to a record already read it is
#          done, marks nothing and writes nothing; and it never moves a mark back.
# The thread itself comes back with show, and its counts and whose turn it is with every list.
#
# AN ANSWERED QUESTION LEAVES THE FOUNDER'S LIST AND IS NEVER PUT BACK (2026-10-12; the table of
# operations below says what is refused and what is done instead). What is left to ask is a NEW
# question that names the old one (add, followsUp); how much a question matters and how much it holds
# up are two words beside it (add; corrected by rank); and a question of parts is answered part by
# part (say, part), each answer a record of its own. The keeper still sees every question, answered or
# not, and every answer: list and show leave nothing out, and inbox hands over each answer once.
#
# A QUESTION THAT NEEDS A PASSKEY (needsPasskey; the audit of 2026-10-16, item 17). A production action is
# taken only on the founder's answer to such a question, given with his fresh passkey on the phone. The
# list ITSELF holds to it, whoever asks: an answer of his to that question - the window's, the words a
# session recorded from chat, a phone answer signed by an unlocked session, or any request that merely
# says a passkey signed it - is refused, with a sentence saying to answer it on the phone with Face ID;
# only words that channels/decisions/Answer.ps1 proves were signed by a trusted passkey, from the relay
# journal's own record of the envelope, are written. The keeper's words under it, and the founder's acts
# (park, unpark), are not answers and are taken as before; so is every word under any other question.
# This file runs in its caller's process, so a request could claim anything about itself: the proof is
# worked out again from the evidence, never read from a flag. And because a caller in the same process
# could also write a record past this file, the operation authorized does not trust the list either: it
# proves the standing answer again, from the record's evidence, each time it is asked - the one question a
# production wrapper asks before it acts (`horde decisions authorized <number>`).
# THE PROOF IS LOADED ONLY WHEN ASKED (Test-HordeDecisionPasskeyAnswer): it reads relay's journal, trust
# store and keys, which costs about half a second to load (measured 2026-10-16, 340 to 510 ms), and every
# other request pays nothing for it.

# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path $PSScriptRoot "Settings.ps1")
. (Join-Path $PSScriptRoot "Store.ps1")
. (Join-Path $PSScriptRoot "Rules.ps1")
. (Join-Path $PSScriptRoot "Definitions.ps1")

# A QUESTION IS NEVER PUT BACK IN FRONT OF THE FOUNDER (his words, 2026-10-12: "once he answers a
# question it goes away from his list, even if there is a follow-up; a follow-up is a brand-new
# question, never the old one reopened in place"). Two requests would put one back, and both are
# refused, each with what to do instead:
#   reopen                       a closed question opened again under its old number;
#   say, the keeper's words that ASK, under an open question that is no longer his turn
#                                (Complete-HordeDecisionSayData): they would pass the turn back to him.
# What is left to ask is asked as a NEW question (add, with followsUp naming the old one), which shows
# him the old question and his answer as folded context. RECORDS ALREADY IN A STORE ARE FACTS: a
# question reopened, or asked again under its number, before this rule stays in front of him as it
# was, once, until he answers it; nothing in a store is rewritten or read differently.
$script:HordeDecisionFollowUpAdvice = 'Ask what is still open as a NEW question: horde decisions add -File <question.json> -FollowsUp {0}. It gets a number of its own and goes to the top of his list, with question {0} and what he answered folded under it.'
$script:HordeDecisionReopenRetired = 'a question is never put back in front of the founder under its old number, so nothing is reopened any more; nothing was written. ' + $script:HordeDecisionFollowUpAdvice

# THE OPERATIONS. Each is named for its definition in schema/decision-request.v1. A write names the
# kind of record it makes and the function that turns a checked request into that record's content; a
# read names the function that answers from the list.
$script:HordeDecisionOperations = [ordered]@{
    # complete: a function that finishes the record's data from the list as it stands at each try, or
    # says the request is answered from the list with nothing written, or says why the list as it
    # stands does not allow it. parts: a function that gives what the answer holds besides the
    # question, from the list and the record's sequence number - the same function for a write and
    # for a repost of it, so the two answers cannot differ.
    add    = @{ writes = $true;  kind = "question-added";    content = "Get-HordeDecisionAddContent";   complete = "Complete-HordeDecisionAddData" }
    update = @{ writes = $true;  kind = "question-updated";  content = "Get-HordeDecisionUpdateContent" }
    close  = @{ writes = $true;  kind = "question-closed";   content = "Get-HordeDecisionCloseContent" }
    # retired: an operation that is no longer done. Its records in the store are read as they always
    # were (decisions/Rules.ps1 applies them); a NEW request is refused with this sentence - {0} is the
    # question's number - after a repost of one recorded before has been answered from its record.
    reopen = @{ writes = $true;  kind = "question-reopened"; content = "Get-HordeDecisionReopenContent"; retired = $script:HordeDecisionReopenRetired }
    rank   = @{ writes = $true;  kind = "question-ranked";   content = "Get-HordeDecisionRankContent" }
    say    = @{ writes = $true;  kind = "message-said";      content = "Get-HordeDecisionSayContent";   complete = "Complete-HordeDecisionSayData"; parts = "Get-HordeDecisionSayParts" }
    "mark-read" = @{ writes = $true; kind = "messages-read"; content = "Get-HordeDecisionMarkContent"; complete = "Complete-HordeDecisionMarkData"; parts = "Get-HordeDecisionMarkParts" }
    list   = @{ writes = $false; read = "Get-HordeDecisionListAnswer" }
    show   = @{ writes = $false; read = "Get-HordeDecisionShowAnswer" }
    # authorized: is the founder's standing answer to a question one his trusted passkey signed? Proven
    # again from its evidence on every ask (A QUESTION THAT NEEDS A PASSKEY, above); refused, with the
    # reason, when it is not.
    authorized = @{ writes = $false; read = "Get-HordeDecisionAuthorizedAnswer" }
    # Answered from the definitions alone: no store is read, so it answers where a list could not.
    kinds  = @{ writes = $false; read = "Get-HordeDecisionKindsAnswer"; noStore = $true }
    inbox  = @{ writes = $false; read = "Get-HordeDecisionInboxAnswer" }
}
# HOW LONG A WRITE KEEPS TRYING is two settings (decisions/Settings.ps1 and its table), written nowhere
# here:
#   decisions.write.raceTries  how many times a write tries for a sequence number before it says it
#     cannot. Each failed try means another writer's record was written, so the default of 200 is 200
#     other writes landing first; a write that still has not won is reported, never spun for ever.
#   decisions.write.heldReads  how many reads in a row may find a record held open by another process
#     before a write gives up. The store has already waited its own 2 s for that record on each read
#     (decisions/Store.ps1), so the default of 5 is about ten seconds - far longer than any writer
#     holds a record, and short enough to wait for at a command line. It has a limit of its own
#     because the tries above were sized for losing a race, which costs milliseconds: measured
#     2026-10-06, counted against them, a write with record 1 held open was still waiting after 40 s
#     and could have waited 400.

function Get-HordeDecisionOperations {
    # The operations, as { name; writes }, for a caller that offers them (a bridge, a help text).
    return @($script:HordeDecisionOperations.Keys | ForEach-Object { [pscustomobject]@{ name = $_; writes = [bool]$script:HordeDecisionOperations[$_].writes } })
}

function Get-HordeDecisionStoreRoot {
    # Where the store is: <HordeHome>\store\decisions. Worked out, never created here: a read must not
    # make folders (core/Home.ps1).
    return (Join-Path (Join-Path (Get-HordeHome) "store") "decisions")
}

function New-HordeDecisionResult {
    # The value of a known answer, schema/decision-result.v1. -State is the list the answer was worked
    # out from, or $null when the request was refused before the store was read; its unreadable and
    # ignored records, and the store's stray files, go into every result, so no caller can show a list
    # without them.
    param([string]$Operation, [string]$Outcome, [string]$Reason = "", $Findings = @(), $State = $null, $More = $null)
    $value = [ordered]@{ schemaVersion = 1; operation = $Operation; outcome = $Outcome; reason = $Reason; findings = [string[]]@($Findings) }
    if ($null -ne $More) { foreach ($k in @($More.Keys)) { $value[$k] = $More[$k] } }
    $unreadable = @(); $ignored = @(); $strays = @(); $later = @()
    if ($null -ne $State) {
        # Records of a kind this version does not know, once for each kind (decisions/Rules.ps1, THE
        # COMPATIBILITY CONTRACT): reported, never hidden, and never called unreadable.
        $later = @($State.notUnderstood.Values | ForEach-Object { [pscustomobject]@{ kind = "$($_.kind)"; count = [int]$_.count; first = [long]$_.first; last = [long]$_.last
            reason = ("its kind '" + $_.kind + "' is not one this version of Horde knows. A later version wrote it: it is kept, it changes nothing this version shows, and it costs no question number") } })
        $strays = @($State.strays | ForEach-Object { [pscustomobject]@{ file = "$($_.file)"; reason = "$($_.reason)" } })
        $unreadable = @($State.unreadable | ForEach-Object { [pscustomobject]@{ sequence = $_.sequence; file = $_.file; reason = $_.reason } })
        $ignored = @($State.ignored | ForEach-Object { [pscustomobject]@{ sequence = $_.sequence; file = $_.file; reason = $_.reason } })
    }
    $value["unreadable"] = $unreadable
    $value["ignored"] = $ignored
    $value["strays"] = $strays
    $value["notUnderstood"] = $later
    return [pscustomobject]$value
}

function Complete-HordeDecisionAnswer {
    # The last step of every operation: the value is checked against schema/decision-result.v1, and
    # only then wrapped as known. A value that does not match is a defect in this module, and is
    # answered as unknown with the findings - never handed on as if it were a result. -Written says
    # what, if anything, is already on disk, so that the unknown does not hide a record that exists.
    param($Value, $Definitions, [datetime]$Now, [string]$Written = "")
    $off = @(Test-HordeSchema -Value $Value -Schema $Definitions.resultSchema)
    if ($off.Count -gt 0) {
        $why = "the result of '" + $Value.operation + "' does not match decision-result.v1 (" + (@($off | Select-Object -First 3) -join "; ") + "), so it is not handed on"
        if ($Written -ne "") { $why = $why + ". " + $Written }
        return (New-HordeUnknown -Reason $why)
    }
    return (New-HordeKnown -Value $Value -ObservedAt $Now)
}

function Get-HordeDecisionAddContent {
    # A checked add request as { body; findings }: body is what the record's data holds besides the
    # number, which only the list can give.
    param($Request, $Definitions)
    $bad = @(Test-HordeSchema -Value $Request.question -Schema $Definitions.questionSchema -Path "question")
    if ($bad.Count -gt 0) { return [pscustomobject]@{ body = $null; findings = $bad } }
    $fields = ConvertTo-HordeDecisionFields -Source $Request.question
    $body = [ordered]@{ question = $fields }
    $found = New-Object System.Collections.ArrayList
    foreach ($f in @(Test-HordeDecisionQuestion -Question $fields -Kinds $Definitions.kinds)) { [void]$found.Add($f) }
    # WHAT STANDS BESIDE THE QUESTION IS RECORDED ONLY WHEN THE REQUEST STATES IT (decisions/Rules.ps1,
    # HOW MUCH A QUESTION MATTERS): a request that names no importance makes a record that names none,
    # which reads as the default - and is byte for byte the record every earlier version wrote.
    foreach ($beside in @("importance", "blocks")) {
        if (-not (Test-HordeDecisionMember -Object $Request -Name $beside)) { continue }
        $stated = Get-HordeDecisionMember -Object $Request -Name $beside
        foreach ($f in @(Test-HordeDecisionRankWord -Name $beside -Word $stated)) { [void]$found.Add($f) }
        $body[$beside] = [string]$stated
    }
    # NEEDS A PASSKEY, the same way: the asker marks a question that changes something important (a
    # production deploy) so that from the phone it is answered only with a fresh passkey. It is not a
    # question field: a field would write needsPasskey false into every new record, and an older
    # reader would refuse every one. So only true is written; false or absent writes nothing, and the
    # record is byte for byte what earlier versions wrote.
    if (Test-HordeDecisionMember -Object $Request -Name "needsPasskey") {
        $stated = Get-HordeDecisionMember -Object $Request -Name "needsPasskey"
        if ($stated -isnot [bool]) { [void]$found.Add("'needsPasskey' is '" + $stated + "', not true or false") }
        elseif ($stated) { $body["needsPasskey"] = $true }
    }
    if (Test-HordeDecisionMember -Object $Request -Name "followsUp") {
        if (Test-HordeDecisionCount -Value $Request.followsUp -Most (Get-HordeDecisionMaxNumber)) { $body["followsUp"] = [int]$Request.followsUp }
        else { [void]$found.Add("'followsUp' is not a question's number: it is a whole number from 1, no larger than " + (Get-HordeDecisionMaxNumber)) }
    }
    return [pscustomobject]@{ body = $body; findings = @($found) }
}

function Complete-HordeDecisionAddData {
    # A FOLLOW-UP NAMES A QUESTION THAT IS THERE. Asked of the list as it stands at each try, and only
    # of a request: a stored record is a fact, and one that names a question the list cannot show is
    # still a question (decisions/Rules.ps1, ConvertTo-HordeDecisionFollowsUpView).
    param($Request, $List, $Data)
    if ($Data.Contains("followsUp")) {
        $old = [int]$Data["followsUp"]
        if ((Get-HordeDecisionNumberStatus -State $List -Number $old) -cne "present") {
            return [pscustomobject]@{ why = ("'followsUp' names question " + $old + ", and the list has no question " + $old + " to show with this one; the highest number given is " + $List.lastNumber); write = $false; more = $null; data = $null }
        }
    }
    return [pscustomobject]@{ why = ""; write = $true; more = $null; data = $Data }
}

function Get-HordeDecisionRankContent {
    # A checked rank request as { body; findings }: the one or two words it changes.
    param($Request, $Definitions)
    $body = [ordered]@{}
    $found = New-Object System.Collections.ArrayList
    foreach ($name in @("importance", "blocks")) {
        if (-not (Test-HordeDecisionMember -Object $Request -Name $name)) { continue }
        $word = Get-HordeDecisionMember -Object $Request -Name $name
        foreach ($f in @(Test-HordeDecisionRankWord -Name $name -Word $word)) { [void]$found.Add($f) }
        $body[$name] = [string]$word
    }
    if ($body.Count -eq 0) { [void]$found.Add("the ranking names neither word, so there is nothing to change: give 'importance' (" + ((Get-HordeDecisionImportances) -join ", ") + "), 'blocks' (" + ((Get-HordeDecisionBlockings) -join ", ") + "), or both") }
    return [pscustomobject]@{ body = $body; findings = @($found) }
}

function Get-HordeDecisionUpdateContent {
    param($Request, $Definitions)
    $wrong = @(Test-HordeSchema -Value $Request.changes -Schema $Definitions.questionSchema -Path "changes")
    if ($wrong.Count -gt 0) { return [pscustomobject]@{ body = $null; findings = $wrong } }
    $fields = ConvertTo-HordeDecisionFields -Source $Request.changes -Partial
    $found = @()
    if ($fields.Count -eq 0) { $found = @("the change names no field, so there is nothing to change; the fields are: " + ((Get-HordeDecisionFieldNames) -join ", ")) }
    # The changed question as a whole is judged after the change is applied to the list, in
    # Invoke-HordeDecisionWrite: a change of kind to "choice" is right or wrong only together with the
    # options the question already has.
    return [pscustomobject]@{ body = [ordered]@{ changes = $fields }; findings = $found }
}

function Get-HordeDecisionCloseContent {
    param($Request, $Definitions)
    return [pscustomobject]@{ body = [ordered]@{ outcome = [string]$Request.outcome }; findings = @(Test-HordeDecisionNote -Text ([string]$Request.outcome) -Name "outcome") }
}

function Get-HordeDecisionReopenContent {
    param($Request, $Definitions)
    return [pscustomobject]@{ body = [ordered]@{ reason = [string]$Request.reason }; findings = @(Test-HordeDecisionNote -Text ([string]$Request.reason) -Name "reason" -OneLine) }
}

function Get-HordeDecisionSayContent {
    # A checked say request as { body; findings }. The words go into the body exactly as they came.
    param($Request, $Definitions)
    $body = [ordered]@{ speaker = [string]$Request.speaker; route = [string]$Request.route; text = [string]$Request.text }
    $found = New-Object System.Collections.ArrayList
    # THE WORDING THE SPEAKER WAS LOOKING AT IS RECORDED ONLY WHEN THE REQUEST STATES IT. Nothing is put
    # in its place: a request without one makes a record without one ("not stated").
    $stated = Test-HordeDecisionMember -Object $Request -Name "wordingVersion"
    $proven = Test-HordeDecisionMember -Object $Request -Name "evidence"
    $evidence = $(if ($proven) { [string]$Request.evidence } else { "" })
    $signed = Test-HordeDecisionMember -Object $Request -Name "signedBy"
    $signedBy = $(if ($signed) { [string]$Request.signedBy } else { "" })
    foreach ($f in @(Test-HordeDecisionSaying -Speaker $body["speaker"] -Route $body["route"] -Actor ([string]$Request.actor) -Text $body["text"] -WordingStated ([bool]$stated) -EvidenceStated ([bool]$proven) -Evidence $evidence -SignedByStated ([bool]$signed) -SignedBy $signedBy)) { [void]$found.Add($f) }
    if ($stated) {
        if (Test-HordeDecisionCount -Value $Request.wordingVersion -Most (Get-HordeDecisionMaxNumber)) { $body["wordingVersion"] = [int]$Request.wordingVersion }
        else { [void]$found.Add("'wordingVersion' is not a wording a question can have: it is a whole number from 1, no larger than " + (Get-HordeDecisionMaxNumber)) }
    }
    # A NOTE AND AN ACT (the owner, 2026-10-07: answers picked up should leave his list, and a
    # reply that asks him nothing must not bring one back). asks=false: the keeper's words tell him
    # something and ask nothing, so the turn stays the keeper's. act: the founder's words in the window
    # record an act of his, park or unpark, and the turn does not pass. Each is recorded only when it
    # says something; a word the rules do not let that speaker say is refused, never dropped.
    foreach ($f in @(Test-HordeDecisionSayMarks -Request $Request -Speaker $body["speaker"] -Route $body["route"])) { [void]$found.Add($f) }
    if ((Test-HordeDecisionMember -Object $Request -Name "asks") -and $Request.asks -eq $false) { $body["asks"] = $false }
    if (Test-HordeDecisionMember -Object $Request -Name "act") { $body["act"] = [string]$Request.act }
    # THE PART ANSWERED (decisions/Rules.ps1, A QUESTION OF PARTS), recorded only when the request names
    # one. It is part of what makes a request the same: the same words to another part are another answer.
    if ((Test-HordeDecisionMember -Object $Request -Name "part") -and $Request.part -is [string]) { $body["part"] = [string]$Request.part }
    # THE EVIDENCE IS KEPT AND NOT HASHED (the route phone, decisions/Rules.ps1). It is the proof of one
    # DELIVERY - the hash of the relay journal record of the envelope that carried the words - and the
    # same answer can arrive in two envelopes: a phone that heard nothing back sends it again. Hashed,
    # the second delivery would be "the id used for a different request" and refused; unhashed, it is
    # the first record answered again, with the first delivery's proof. The first answer wins, and the
    # record keeps the proof of the one that won.
    if ($proven) { $body["evidence"] = $evidence }
    # WHO SIGNED IS KEPT AND NOT HASHED EITHER (signedBy, decisions/Rules.ps1). The relay channel makes the
    # request's id from the sender's key id, so one id never comes with two of them; and an answer
    # recorded before records named the passkey, handed over again after, must be that first record
    # answered again - which names none - never "the id used for a different request".
    if ($signed) { $body["signedBy"] = $signedBy }
    return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("evidence", "signedBy") }
}

$script:HordeDecisionPasskeyProofFile = Join-Path (Split-Path -Parent $PSScriptRoot) "channels\decisions\Answer.ps1"

function Get-HordeDecisionHomeOfStore {
    # The Horde home whose relay journal, trust store and keys prove the answers of the store -Root: ""
    # for Horde's own (no -Root given: the store is Get-HordeDecisionStoreRoot's, under that home), the
    # folder two above a store named <home>\store\decisions, and $null for a store in no home - whose
    # answers have no journal to be proven from, so none of them is.
    param([string]$Root)
    if ($Root -ceq "") { return "" }
    $full = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@([char]92, [char]47))
    $store = [System.IO.Path]::GetDirectoryName($full)
    if ([System.IO.Path]::GetFileName($full) -ne "decisions" -or [string]::IsNullOrEmpty($store) -or [System.IO.Path]::GetFileName($store) -ne "store") { return $null }
    return [System.IO.Path]::GetDirectoryName($store)
}

function Test-HordeDecisionPasskeyAnswer {
    # Did a trusted passkey sign exactly these words as the answer to question -Number (the header, A
    # QUESTION THAT NEEDS A PASSKEY)? channels/decisions/Answer.ps1's proof, its file loaded here the
    # first time it is asked and only then: { ok; reason; keyId; signedAt }. -Root is the store's folder,
    # as Invoke-HordeDecision was given it, which names the home the proof is read from.
    param([string]$Id, [int]$Number, [AllowEmptyString()][string]$Text, [string]$Part = "", [int]$WordingVersion = 0,
        [string]$Evidence = "", [string]$SignedBy = "", [string]$Root = "", $Now = $null)
    $proofHome = Get-HordeDecisionHomeOfStore -Root $Root
    if ($null -eq $proofHome) { return [pscustomobject]@{ ok = $false; reason = "this store is in no Horde home, so there is no relay journal to prove a passkey from"; keyId = ""; signedAt = [long]-1 } }
    if ($null -eq (Get-Command -Name "Test-HordeDecisionsChannelPasskeyAnswer" -CommandType Function -ErrorAction SilentlyContinue)) { . $script:HordeDecisionPasskeyProofFile }
    return (Test-HordeDecisionsChannelPasskeyAnswer -Id $Id -Number $Number -Text $Text -Part $Part -WordingVersion $WordingVersion -Evidence $Evidence -SignedBy $SignedBy -HordeHome $proofHome -Now $Now)
}

function Get-HordeDecisionPasskeyRefusal {
    # Why an answer of the founder's to a question that needs a passkey is not taken, in words the person
    # who gave it can act on (the header, A QUESTION THAT NEEDS A PASSKEY). -Why: what the proof found.
    param([int]$Number, [string]$Route, [string]$Why = "")
    if ($Route -ceq "window") { return ("question " + $Number + " needs your passkey: answer it on your phone with Face ID. Words typed in the window are not taken for it") }
    if ($Route -ceq "chat-recorded") { return ("question " + $Number + " needs the founder's passkey: ask him to answer it on his phone with Face ID. His words recorded from chat are not taken for it") }
    if ($Route -ceq "phone") { return ("question " + $Number + " needs your passkey: answer it on your phone with Face ID. This answer is not proven signed by your passkey: " + $Why) }
    return ("question " + $Number + " needs the founder's passkey: only his answer on his phone with Face ID is taken for it, not words " + (Get-HordeDecisionRouteShown -Route $Route))
}

function Complete-HordeDecisionSayData {
    # THE KEEPER'S WORDS THAT ASK ARE SAID ONLY WHILE THE QUESTION IS STILL IN FRONT OF THE FOUNDER
    # (above, A QUESTION IS NEVER PUT BACK). Under an open question that is no longer his turn - he
    # has answered it - they would pass the turn back to him: refused, with the two things that can be
    # done instead. A note (asks false) asks nothing and is always taken; so are words under a closed
    # question, which take no turn; and so is every word of his own - but for one rule, below.
    # -Root and -Now: the store's folder and the writer's clock, for the passkey's proof.
    param($Request, $List, $Data, [string]$Root = "", $Now = $null)
    $number = [int]$Data["number"]
    # HIS ANSWER TO A QUESTION THAT NEEDS A PASSKEY is taken only with the proof of one (the header, A
    # QUESTION THAT NEEDS A PASSKEY): asked of the question as the list stands at this try, and proven
    # from the evidence the request carries, whatever else it says of itself. An act of his (park,
    # unpark) answers nothing and is not asked.
    if ("$($Data['speaker'])" -ceq (Get-HordeDecisionFirstTurn) -and -not $Data.Contains("act") -and $List.questions.ContainsKey($number)) {
        $asked = $List.questions[$number]
        if ((Test-HordeDecisionMember -Object $asked -Name "needsPasskey") -and [bool]$asked["needsPasskey"]) {
            $proof = Test-HordeDecisionPasskeyAnswer -Id ([string]$Request.id) -Number $number -Text ([string]$Data["text"]) `
                -Part $(if ($Data.Contains("part")) { [string]$Data["part"] } else { "" }) -WordingVersion $(if ($Data.Contains("wordingVersion")) { [int]$Data["wordingVersion"] } else { 0 }) `
                -Evidence $(if ($Data.Contains("evidence")) { [string]$Data["evidence"] } else { "" }) -SignedBy $(if ($Data.Contains("signedBy")) { [string]$Data["signedBy"] } else { "" }) -Root $Root -Now $Now
            if (-not $proof.ok) { return [pscustomobject]@{ why = (Get-HordeDecisionPasskeyRefusal -Number $number -Route "$($Data['route'])" -Why $proof.reason); write = $false; more = $null; data = $null } }
        }
    }
    $asking = (-not $Data.Contains("asks")) -and (-not $Data.Contains("act"))
    if ($asking -and (Get-HordeDecisionNoteSpeakers) -ccontains "$($Data['speaker'])" -and $List.questions.ContainsKey($number)) {
        $question = $List.questions[$number]
        if ("$($question.state)" -ceq "open" -and "$($question.turn)" -cne (Get-HordeDecisionFirstTurn)) {
            return [pscustomobject]@{ why = ("question " + $number + " has been answered and is off the founder's list, and words that ask him something would put it back in front of him. " + ($script:HordeDecisionFollowUpAdvice -f $number) + " To tell him something that asks nothing, say it as a note (reply -Note)"); write = $false; more = $null; data = $null }
        }
    }
    return [pscustomobject]@{ why = ""; write = $true; more = $null; data = $Data }
}

function Get-HordeDecisionSayParts {
    # What a say answers with besides the question: the message of record -Sequence, as the list has it.
    param($List, [long]$Sequence)
    foreach ($question in $List.questions.Values) {
        foreach ($message in $question.thread) {
            if ([long]$message.sequence -eq $Sequence) { return [ordered]@{ message = (ConvertTo-HordeDecisionMessageView -Message $message -State $List) } }
        }
    }
    return [ordered]@{}
}

function Get-HordeDecisionReaderProblem {
    # Why -Actor has no inbox, or "": the one sentence both the reading and the marking refuse with.
    param([string]$Actor)
    $readers = @(Get-HordeDecisionReaders)
    if ($readers -ccontains $Actor) { return "" }
    return ("'" + $Actor + "' has no inbox; the roles that have one are: " + ($readers -join ", "))
}

function Get-HordeDecisionInboxAnswer {
    # What others have said that the actor has not read: every question, oldest first, each message
    # with its question's number and title as it reads now. upTo is the last message's sequence
    # number (0 for none): what a caller that then marks names. IT READS, AND NOTHING ELSE.
    param($Request, $State, $Definitions, [datetime]$Now)
    $reader = [string]$Request.actor
    $why = Get-HordeDecisionReaderProblem -Actor $reader
    if ($why -ne "") { return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation "inbox" -Outcome "refused" -Reason $why -Findings @($why) -State $State) -Definitions $Definitions -Now $Now) }
    $last = [long]0
    $views = New-Object System.Collections.ArrayList
    foreach ($item in @(Get-HordeDecisionMessagesFor -State $State -Reader $reader)) {
        $last = [long]$item.message.sequence
        [void]$views.Add([pscustomobject]@{ number = [int]$item.question.number; title = "$($item.question.title)"; state = "$($item.question.state)"; message = (ConvertTo-HordeDecisionMessageView -Message $item.message -State $State) })
    }
    $value = New-HordeDecisionResult -Operation "inbox" -Outcome "done" -State $State -More ([ordered]@{ messages = @($views); upTo = $last })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Get-HordeDecisionMarkContent {
    # A checked mark-read request as { body; findings }. The body is what is hashed: the record marked
    # up to. The reader is the actor.
    param($Request, $Definitions)
    $found = New-Object System.Collections.ArrayList
    $upTo = [long]0
    if (Test-HordeDecisionCount -Value $Request.upTo -Most (Get-HordeDecisionMaxSequence)) { $upTo = [long]$Request.upTo }
    else { [void]$found.Add("'upTo' is not a record's sequence number: it is a whole number from 1, no larger than " + (Get-HordeDecisionMaxSequence)) }
    $why = Get-HordeDecisionReaderProblem -Actor ([string]$Request.actor)
    if ($why -ne "") { [void]$found.Add($why) }
    return [pscustomobject]@{ body = [ordered]@{ upTo = $upTo }; findings = @($found) }
}

function Complete-HordeDecisionMarkData {
    # IDEMPOTENT, AND NEVER BACKWARDS: when the reader has already read up to that record or past it,
    # the marking is done, marks nothing and writes nothing - whatever id it carries. Otherwise the
    # record says the reader has read up to the record NAMED, and nothing beyond it.
    param($Request, $List, $Data)
    $reader = [string]$Request.actor
    $upTo = [long]$Data["upTo"]
    if ($upTo -le (Get-HordeDecisionReadMark -State $List -Reader $reader)) {
        return [pscustomobject]@{ why = ""; write = $false; more = ([ordered]@{ upTo = $upTo; marked = 0 }); data = $null }
    }
    return [pscustomobject]@{ why = ""; write = $true; more = $null; data = [ordered]@{ reader = $reader; upTo = $upTo } }
}

function Get-HordeDecisionMarkParts {
    # What a marking answers with: the record it marked up to, and how many messages that marked -
    # those between how far the reader had read before it and how far it says. Worked out from the
    # list, so a repost of the request is answered as the first answer was.
    param($List, [long]$Sequence)
    if (-not $List.readEvents.ContainsKey($Sequence)) { return [ordered]@{} }
    $marking = $List.readEvents[$Sequence]
    $items = @(Get-HordeDecisionMessagesFor -State $List -Reader "$($marking.reader)" -After ([long]$marking.from) -UpTo ([long]$marking.upTo))
    return [ordered]@{ upTo = [long]$marking.upTo; marked = $items.Count }
}

function Get-HordeDecisionNumberAnswer {
    # For an operation about one question: $null when the list has it, else the answer to give -
    # absent when the number was never given, unknown when its record cannot be read.
    param($State, [long]$Number, [string]$Operation)
    $status = "absent"
    if ($Number -le [int]::MaxValue) { $status = Get-HordeDecisionNumberStatus -State $State -Number ([int]$Number) }
    if ($status -eq "present") { return $null }
    if ($status -eq "unreadable") {
        # The records that may hold it: every unreadable one, and every one set aside as a later kind,
        # since a set-aside record's number raises the floor too (decisions/Rules.ps1, the contract).
        $which = @(@($State.unreadable | ForEach-Object { "record " + $_.sequence + " (" + $_.file + "): " + $_.reason }) + @($State.notUnderstood.Values | ForEach-Object { $(if ([long]$_.first -eq [long]$_.last) { "record " + $_.first } else { "records " + $_.first + " to " + $_.last }) + " of the kind '" + $_.kind + "', set aside as not understood by this version" })) -join "; "
        return (New-HordeUnknown -Reason ("question " + $Number + " cannot be read, so '" + $Operation + "' did nothing: its number was given, or may have been, to a record that cannot be read. " + $which))
    }
    return (New-HordeAbsent -Note ("there is no question " + $Number + "; the highest number given is " + $State.lastNumber))
}

function Get-HordeDecisionListAnswer {
    param($Request, $State, $Definitions, [datetime]$Now)
    $want = "open"
    # The listed words in any case: a person types this one, and "ALL" means all. Nothing else is
    # taken; what is refused is named back only when it is letters and hyphens, so that a refusal
    # never repeats text of another kind.
    if (Test-HordeDecisionMember -Object $Request -Name "state") { $want = ([string]$Request.state).ToLowerInvariant() }
    $states = @(Get-HordeDecisionStates)
    if ($want -cne "all" -and $states -cnotcontains $want) {
        $named = "that"
        if ($want -cmatch '\A[a-z][a-z-]{0,31}\z') { $named = "'" + $want + "'" }
        $why = $named + " is not a state a question can be in; give one of: " + ($states -join ", ") + ", or all"
        return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation "list" -Outcome "refused" -Reason $why -Findings @($why) -State $State) -Definitions $Definitions -Now $Now)
    }
    # WITH MESSAGES, each thread as show gives it: one read of the store for every question's
    # conversation, where a show per question would read it once a question (channels/decisions).
    $withMessages = ((Test-HordeDecisionMember -Object $Request -Name "messages") -and $Request.messages -eq $true)
    $counts = [ordered]@{}
    foreach ($s in $states) { $counts[$s] = 0 }
    $views = New-Object System.Collections.ArrayList
    foreach ($question in $State.questions.Values) {
        if ($counts.Contains("$($question.state)")) { $counts["$($question.state)"] = [int]$counts["$($question.state)"] + 1 }
        if ($want -ceq "all" -or "$($question.state)" -ceq $want) { [void]$views.Add((ConvertTo-HordeDecisionView -Question $question -State $State -Messages:$withMessages)) }
    }
    $value = New-HordeDecisionResult -Operation "list" -Outcome "done" -State $State -More ([ordered]@{ questions = @($views); counts = [pscustomobject]$counts })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Get-HordeDecisionShowAnswer {
    param($Request, $State, $Definitions, [datetime]$Now)
    $number = [long]$Request.number
    $missing = Get-HordeDecisionNumberAnswer -State $State -Number $number -Operation "show"
    if ($null -ne $missing) { return $missing }
    $view = ConvertTo-HordeDecisionView -Question $State.questions[[int]$number] -State $State -Messages
    $value = New-HordeDecisionResult -Operation "show" -Outcome "done" -State $State -More ([ordered]@{ number = [int]$number; question = $view })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Get-HordeDecisionAuthorizedAnswer {
    # MAY A PRODUCTION ACTION GO AHEAD ON QUESTION -number? Done only when the founder's STANDING ANSWER -
    # his newest words under it that answer it (an act, park or unpark, answers nothing), to the part the
    # request names or else to the whole question - is proven, NOW, signed by a passkey this machine
    # trusts now, to the wording the question has now (the header, A QUESTION THAT NEEDS A PASSKEY).
    # Refused otherwise, with the reason; nothing is ever written. It says THAT he signed and WHAT he
    # signed (authorization.text): whether his words say yes is for the asker to read.
    param($Request, $State, $Definitions, [datetime]$Now, [string]$Root = "")
    $number = [long]$Request.number
    $notThere = Get-HordeDecisionNumberAnswer -State $State -Number $number -Operation "authorized"
    if ($null -ne $notThere) { return $notThere }
    $question = $State.questions[[int]$number]
    $part = ""
    if (Test-HordeDecisionMember -Object $Request -Name "part") { $part = [string]$Request.part }
    $what = $(if ($part -ceq "") { "question " + $number } else { "part (" + $part + ") of question " + $number })
    $no = { param($why) return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation "authorized" -Outcome "refused" -Reason $why -Findings @($why) -State $State -More ([ordered]@{ number = [int]$number })) -Definitions $Definitions -Now $Now) }
    $standing = $null
    foreach ($m in @($question.thread)) { if ("$($m.speaker)" -ceq (Get-HordeDecisionFirstTurn) -and "$($m.act)" -ceq "" -and "$($m.part)" -ceq $part) { $standing = $m } }
    if ($null -eq $standing) { return (& $no ($what + " has no answer of the founder's: ask him to answer it on his phone with Face ID")) }
    $at = "the founder's standing answer to " + $what + " (record " + $standing.sequence + ")"
    if ("$($standing.route)" -cne "phone") { return (& $no ($at + " was " + (Get-HordeDecisionRouteShown -Route "$($standing.route)") + ", and only his answer on his phone with Face ID authorizes it")) }
    if (-not [bool]$standing.wordingStated -or [int]$standing.wordingVersion -ne [int]$question.wordingVersion) { return (& $no ($at + " was given to wording " + $standing.wordingVersion + ", and the question is now at wording " + $question.wordingVersion + ": he has not answered what it says now")) }
    # The record's own id, from the list: the proof holds it to the id made from the signed answer.
    $id = ""
    foreach ($k in @($State.ids.Keys)) { if ([long]$State.ids[$k].sequence -eq [long]$standing.sequence) { $id = "$k"; break } }
    $proof = Test-HordeDecisionPasskeyAnswer -Id $id -Number ([int]$number) -Text ([string]$standing.text) -Part $part -WordingVersion ([int]$standing.wordingVersion) `
        -Evidence "$($standing.evidence)" -SignedBy "$($standing.signedBy)" -Root $Root -Now $Now
    if (-not $proof.ok) { return (& $no ($at + " is not proven signed by a passkey this machine trusts: " + $proof.reason)) }
    $granted = [ordered]@{ sequence = [long]$standing.sequence; signedBy = $proof.keyId; signedAt = [long]$proof.signedAt; wordingVersion = [int]$standing.wordingVersion; text = [string]$standing.text }
    if ($part -cne "") { $granted["part"] = $part }
    $value = New-HordeDecisionResult -Operation "authorized" -Outcome "done" -State $State -More ([ordered]@{ number = [int]$number; authorization = [pscustomobject]$granted })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Get-HordeDecisionKindsAnswer {
    # The table of question kinds (decisions/question-kinds.json, read by decisions/Definitions.ps1), as
    # an answer. It is an operation so that every caller gets the one table from the one API: a caller
    # across a link cannot open this checkout's file, and one that could would be a second reader of it.
    param($Request, $State, $Definitions, [datetime]$Now)
    $value = New-HordeDecisionResult -Operation "kinds" -Outcome "done" -More ([ordered]@{ kinds = $Definitions.kinds })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Read-HordeDecisionState {
    # The store's records and the list worked out from them, as { state; reason; busy; list }. state
    # is the store's own (ok, absent or unknown); busy is the first record another process still holds
    # open, or $null.
    #
    # KNOWN COST, LEFT AS IT IS ON PURPOSE. Every operation reads and checks every record again.
    # Measured 2026-10-06 on a throttled machine, 81 records: reading and parsing the files 130 ms,
    # checking each against its schemas 1128 ms, checking the list result of 81 questions 1292 ms;
    # 3.4 s for one list, about 40 ms a record, nearly all of it schema checking and almost none of
    # it the disk. Nothing is cached on disk, because a cache is a second copy of the truth, and the
    # store is the only one. A caller that stays alive (a window) can keep the list it has in memory
    # and fold in only the records it has not seen: the records never change, and their order is
    # their names.
    param([string]$Root, $Definitions)
    $loaded = Get-HordeDecisionRecords -Root $Root
    if ($loaded.state -ceq "unknown") { return [pscustomobject]@{ state = "unknown"; reason = $loaded.reason; busy = $null; list = $null } }
    $busy = @($loaded.records | Where-Object { $_.kind -ceq "busy" }) | Select-Object -First 1
    $list = ConvertTo-HordeDecisionState -Records $loaded.records -Definitions $Definitions
    foreach ($stray in @($loaded.strays)) { [void]$list.strays.Add($stray) }
    return [pscustomobject]@{ state = $loaded.state; reason = $loaded.reason; busy = $busy; list = $list }
}

function Invoke-HordeDecisionWrite {
    # One write: see "HOW A WRITE STAYS CORRECT" in the header. -Request has passed its schema and the
    # secret check.
    param([string]$Operation, $Request, [string]$Root, $Definitions, [datetime]$Now)
    $entry = $script:HordeDecisionOperations[$Operation]
    $refuse = { param($why, $found, $list) return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $Operation -Outcome "refused" -Reason $why -Findings $found -State $list) -Definitions $Definitions -Now $Now) }

    # WHO MAY WRITE THIS KIND OF RECORD is the rules' answer, by kind: the keepers of the list for a
    # question's own records, the speakers for what is said under one.
    $actor = [string]$Request.actor
    $allowed = Get-HordeDecisionKindActors -Kind $entry.kind
    if (@($allowed.roles) -cnotcontains $actor) {
        $why = "'" + $actor + "' is not a role that may " + $allowed.may + "; the roles that may are: " + (@($allowed.roles) -join ", ")
        return (& $refuse $why @($why) $null)
    }
    $content = & $entry.content $Request $Definitions
    $about = Get-HordeDecisionKindAbout -Kind $entry.kind
    $hasNumber = Test-HordeDecisionMember -Object $Request -Name "number"
    $number = [long]0
    if ($hasNumber) { $number = [long]$Request.number }
    $requestHash = ""
    if ($null -ne $content.body) {
        # What makes two requests the same is the body less the members a content function names as
        # unhashed (the evidence of a say: Get-HordeDecisionSayContent says why).
        $sameness = [ordered]@{}
        $unhashed = @()
        if ($null -ne $content.PSObject.Properties["unhashed"]) { $unhashed = @($content.unhashed) }
        foreach ($k in @($content.body.Keys)) { if ($unhashed -cnotcontains $k) { $sameness[$k] = $content.body[$k] } }
        $hashed = [ordered]@{ operation = $Operation; actor = $actor; number = $number; body = $sameness }
        $requestHash = Get-HordeDecisionHash -Value $hashed
    }
    $id = [string]$Request.id

    $raceTries = Get-HordeDecisionSetting -Name "decisions.write.raceTries"
    $heldReads = Get-HordeDecisionSetting -Name "decisions.write.heldReads"
    $busyReads = 0
    for ($attempt = 1; $attempt -le $raceTries; $attempt++) {
        $read = Read-HordeDecisionState -Root $Root -Definitions $Definitions
        if ($read.state -ceq "unknown") { return (New-HordeUnknown -Reason ("nothing was written: " + $read.reason)) }
        if ($null -ne $read.busy) {
            # A record is still open in another process after the store's own wait. Its content decides
            # whether this request may be written, so this request waits for it rather than guess -
            # for about ten seconds, and then says which record, and that nothing was written.
            $busyReads++
            if ($busyReads -ge $heldReads) {
                return (New-HordeUnknown -Reason ("nothing was written: another process holds record " + $read.busy.sequence + " open, and still did after " + $busyReads + " reads that each waited for it. Try again when it has let go"))
            }
            continue
        }
        $list = $read.list

        # A REPOST IS ANSWERED BEFORE THE REQUEST IS JUDGED: what was recorded stands.
        if ($list.ids.ContainsKey($id)) {
            $prior = $list.ids[$id]
            if ($requestHash -ne "" -and $prior.requestHash -ceq $requestHash) {
                # "REPLAYED" SAYS "THIS WAS RECORDED", so the record is flushed to disk before it is said.
                # A save that answered "unconfirmed" left its record in place, and nothing records which
                # saves those were; so every repost confirms, by the same flush the move makes. If that
                # flush fails the answer is unknown again - never "replayed" on the strength of it.
                $sure = "unconfirmed"
                try { $sure = Confirm-HordeDecisionRecord -Root $Root -Sequence ([long]$prior.sequence) } catch { $sure = "unconfirmed" }
                if ($sure -cne "confirmed") {
                    return (New-HordeUnknown -Reason ("record " + $prior.sequence + " holds this request, but it could not be confirmed written through to the disk (" + $sure + "), so it is NOT reported as saved. Send the same request again, with the same id"))
                }
                $more = [ordered]@{ sequence = $prior.sequence }
                if ([int]$prior.number -ge 1) { $more["number"] = [int]$prior.number }
                if ($list.questions.ContainsKey([int]$prior.number)) { $more["question"] = ConvertTo-HordeDecisionView -Question $list.questions[[int]$prior.number] -State $list }
                if ($entry.ContainsKey("parts")) { $again = & $entry.parts $list ([long]$prior.sequence); foreach ($k in @($again.Keys)) { $more[$k] = $again[$k] } }
                return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $Operation -Outcome "replayed" -State $list -More $more) -Definitions $Definitions -Now $Now)
            }
            $why = "the id " + $id + " was already used for a different request (record " + $prior.sequence + ", " + $prior.kind + "); nothing was written. A new request needs a new id"
            return (& $refuse $why @($why) $list)
        }
        # AN OPERATION THAT IS NO LONGER DONE (the table says which, and why) is refused here: after a
        # repost of a request recorded before has been answered from its record, and before anything else.
        # A number that was never given is still answered as absent: that is a fact about the list,
        # and the sentence below would name a question that does not exist.
        if ($entry.ContainsKey("retired")) {
            if ($hasNumber) { $gap = Get-HordeDecisionNumberAnswer -State $list -Number $number -Operation $Operation; if ($null -ne $gap) { return $gap } }
            $gone = ("$($entry.retired)" -f $number)
            return (& $refuse $gone @($gone) $list)
        }
        if (@($content.findings).Count -gt 0) {
            return (& $refuse ("the request breaks " + @($content.findings).Count + " rule(s); nothing was written") @($content.findings) $list)
        }
        if ($hasNumber) {
            $not = Get-HordeDecisionNumberAnswer -State $list -Number $number -Operation $Operation
            if ($null -ne $not) { return $not }
        }

        # THE RECORD, built as text and read back, so that what is checked and applied below is exactly
        # what a later reader will parse - not the objects it was built from.
        $data = [ordered]@{}
        if ($about -ceq "question") { if ($hasNumber) { $data["number"] = [int]$number } else { $data["number"] = Get-HordeDecisionNextNumber -State $list } }
        foreach ($k in @($content.body.Keys)) { $data[$k] = $content.body[$k] }
        if ($entry.ContainsKey("complete")) {
            $step = & $entry.complete $Request $list $data $Root $Now
            if ("$($step.why)" -ne "") { return (& $refuse ("nothing was written: " + $step.why) @("$($step.why)") $list) }
            # Answered from the list as it stands, with nothing to write.
            if (-not $step.write) { return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $Operation -Outcome "done" -State $list -More $step.more) -Definitions $Definitions -Now $Now) }
            $data = $step.data
        }
        $sequence = [long]$list.lastSequence + 1
        $envelope = [ordered]@{
            schemaVersion = 1; sequence = $sequence; id = $id; kind = $entry.kind
            at = $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
            actor = $actor; requestHash = $requestHash; data = $data
        }
        $text = ConvertTo-Json -InputObject $envelope -Compress -Depth 12
        $record = [pscustomobject]@{ sequence = $sequence; file = (Get-HordeDecisionRecordName -Sequence $sequence); kind = "ok"; data = (ConvertFrom-HordeJson $text); reason = "" }
        # The list's problems as they stood, kept for a refusal: applying the record below adds the
        # unwritten record itself to them when it does not apply.
        $before = [pscustomobject]@{ unreadable = @($list.unreadable); ignored = @($list.ignored); strays = @($list.strays); notUnderstood = $list.notUnderstood }
        $why = Add-HordeDecisionRecordToState -State $list -Record $record -Definitions $Definitions
        if ($why -ne "") { return (& $refuse ("nothing was written: " + $why) @($why) $before) }
        $question = $null
        if ($about -ceq "question") { $question = $list.questions[[int]$data["number"]] }
        if ($Operation -ceq "update") {
            $found = @(Test-HordeDecisionQuestion -Question $question -Kinds $Definitions.kinds)
            if ($found.Count -gt 0) { return (& $refuse ("the question as changed would break " + $found.Count + " rule(s); nothing was written") $found $before) }
        }

        $made = ""
        try { $made = Add-HordeDecisionRecord -Root $Root -Sequence $sequence -Text $text }
        catch { return (New-HordeUnknown -Reason ("record " + $sequence + " could not be written, so nothing changed") -ErrorRecord $_) }
        # THE RECORD HAS ITS PLACE, AND NOTHING SAYS IT IS ON DISK (decisions/Store.ps1, "unconfirmed").
        # Not "done": the caller would be told its words are saved on the strength of a flush that
        # failed. Not "nothing was written": the record is there, and every reader sees it. And not
        # another turn of this loop, which would find the record by its id and answer "replayed" -
        # the same claim in other words.
        if ($made -ceq "unconfirmed") {
            return (New-HordeUnknown -Reason ("record " + $sequence + " has its place in the store, but it could not be confirmed written through to the disk, so it is NOT reported as saved. Send the same request again, with the same id: it is answered from the record if the record is still there"))
        }
        if ($made -cne "created") { continue }
        $more = [ordered]@{ sequence = $sequence; attempts = $attempt }
        if ($null -ne $question) { $more["number"] = [int]$data["number"]; $more["question"] = (ConvertTo-HordeDecisionView -Question $question -State $list) }
        if ($entry.ContainsKey("parts")) { $beside = & $entry.parts $list $sequence; foreach ($k in @($beside.Keys)) { $more[$k] = $beside[$k] } }
        $value = New-HordeDecisionResult -Operation $Operation -Outcome "done" -State $list -More $more
        return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now -Written ("Record " + $sequence + " WAS written"))
    }
    return (New-HordeUnknown -Reason ("nothing was written: " + $raceTries + " tries each found another writer had taken the next sequence number first"))
}

function Invoke-HordeDecision {
    # Do one operation. -Operation is a name from Get-HordeDecisionOperations; -Request is plain data
    # matching that operation's definition in schema/decision-request.v1 (a hashtable, or an object
    # read from JSON). Returns a core/Tristate.ps1 answer; see the header for what its states mean.
    #
    # -Root is the store folder, for a caller that names the one it made (a test); without it the
    # store is Horde's own, under HORDE_HOME. -Now is the writer's clock, for the same caller.
    param([Parameter(Mandatory = $true)][string]$Operation, $Request = $null, [string]$Root = "", [datetime]$Now = [datetime]::UtcNow)
    $definitions = Get-HordeDecisionDefinitions
    $refuse = { param($name, $why, $found) return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $name -Outcome "refused" -Reason $why -Findings $found) -Definitions $definitions -Now $Now) }

    $entry = $null
    if ($Operation -cmatch '\A[a-z][a-z-]{0,31}\z') { $entry = $script:HordeDecisionOperations[$Operation] }
    if ($null -eq $entry) {
        $why = "that is not an operation on the decisions list; the operations are: " + (@($script:HordeDecisionOperations.Keys) -join ", ")
        return (& $refuse "unknown" $why @($why))
    }
    # PLAIN DATA, PROVEN: the request is written as JSON and read back, which is exactly what crossing
    # a link would do to it. Whatever the caller built it from - a hashtable, typed objects - the
    # checks below see only what would arrive.
    # Named $plain, not $request: variable names ignore case, so that would be the parameter itself.
    $plain = $null
    try {
        if ($null -ne $Request) { $plain = ConvertFrom-HordeJson (ConvertTo-Json -InputObject $Request -Compress -Depth 12) }
    } catch {
        $why = "the request is not plain data that can be written as JSON: " + $_.Exception.Message
        return (& $refuse $Operation $why @($why))
    }
    if ($null -eq $plain) { $plain = [pscustomobject]@{} }
    $secrets = @(Find-HordeDecisionSecrets -Value $plain)
    if ($secrets.Count -gt 0) { return (& $refuse $Operation ("the request holds what looks like a secret in " + $secrets.Count + " place(s); nothing was written") $secrets) }
    $shapeSchema = Get-HordeDecisionMember -Object $definitions.requestSchema.definitions -Name $Operation
    $shape = @(Test-HordeSchema -Value $plain -Schema $shapeSchema -Path "request" -Root $definitions.requestSchema)
    if ($shape.Count -gt 0) { return (& $refuse $Operation ("the request is not what '" + $Operation + "' takes; nothing was done") $shape) }
    # A NUMBER NO QUESTION CAN HAVE IS ANSWERED HERE, BEFORE ANYTHING CASTS IT. 1e30 passes the schema's
    # "type": "integer", and the cast to a 64-bit number below it threw instead of answering (measured
    # 2026-10-06: show and close). No store need be read to know there is no such question.
    if ((Test-HordeDecisionMember -Object $plain -Name "number") -and -not (Test-HordeDecisionCount -Value $plain.number -Most (Get-HordeDecisionMaxNumber))) {
        return (New-HordeAbsent -Note ("there is no question " + $plain.number + ": no question has a number above " + (Get-HordeDecisionMaxNumber)))
    }

    if ($entry.ContainsKey("noStore")) { return (& $entry.read $plain $null $definitions $Now) }
    if ($Root -eq "") {
        try { $Root = Get-HordeDecisionStoreRoot }
        catch { return (New-HordeUnknown -Reason "the decisions store could not be found" -ErrorRecord $_) }
    }
    # THE SETTINGS, BEFORE THE STORE IS TOUCHED. An override file that failed its checks refuses every
    # setting (decisions/Settings.ps1), and an operation that went ahead would be running on defaults a
    # person had tried to replace - or would answer at all only because its path happened to need no
    # setting. So every operation on the store answers unknown, in the settings' own sentence: the file
    # and every problem in it. Asked AFTER the store is found, so that a home that cannot be worked out
    # is still said as that, by the lines above; with -Root given and no home, the settings cannot be
    # found either, and core/Home's own words are the reason.
    $unfit = ""
    try { $unfit = Get-HordeDecisionSettingsProblem } catch { $unfit = "$($_.Exception.Message)" }
    if ($unfit -ne "") { return (New-HordeUnknown -Reason $unfit) }
    if ($entry.writes) { return (Invoke-HordeDecisionWrite -Operation $Operation -Request $plain -Root $Root -Definitions $definitions -Now $Now) }
    $read = Read-HordeDecisionState -Root $Root -Definitions $definitions
    if ($read.state -ceq "unknown") { return (New-HordeUnknown -Reason $read.reason) }
    # -Root, beside what every read takes: the store's folder as given, which names the home the operation
    # authorized proves a passkey from. The other reads take no more than they did (it goes to their $args).
    return (& $entry.read $plain $read.list $definitions $Now $Root)
}
