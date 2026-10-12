# decisions/Rules.ps1 - what the decisions records mean, and what may be written.
#
# THE ONE JOB of this file is to turn the records of the store into the current list of questions, and
# to say what a question must hold. Every function is pure: values in, values out. It opens no file,
# reads no clock, and knows nothing of who is calling or how a question is shown. decisions/Store.ps1
# reads the records; decisions/Definitions.ps1 reads the schemas and the kind table from disk and hands
# them in as -Definitions; decisions/Operations.ps1 is the only caller.
#
# ONE FUNCTION PER EVENT KIND DECIDES BOTH QUESTIONS. "May this be written?" and "what does this record
# do to the list?" are the same question asked at two moments, so each kind has one function that
# applies a record to the list or says why it cannot. Operations.ps1 runs it on the record it is about
# to write, against the list as it stands, and refuses the request if it says no; the fold runs it on
# every stored record. Two functions would be two statements of one rule, and would drift.
#
# ADDING AN EVENT KIND is one entry in $HordeDecisionEventKinds and its function below, plus its data
# definition in schema/decision-event.v1. Nothing else in this file changes.
#
# A SMALL CONVERSATION UNDER EACH QUESTION. Two kinds are not about the question's words at all:
# "message-said" (someone said something under question N) and "messages-read" (a reader has read
# what others said, up to a record). What they mean is worked out here, like everything else:
#   - A MESSAGE IS KEPT, ALWAYS. Words said under a closed question are kept and flagged "arrived
#     after closing"; words said to a wording the question had already left WHEN THEY WERE SAID are
#     kept and flagged "said to an earlier wording". Both are judged at the moment of the record, in
#     store order, never against today: a later rewording does not flag words said before it, and a
#     later reopening does not unflag words that arrived while it was closed. Neither is ever
#     dropped, and neither changes the question: speaking never moves a number, a wording or a
#     state, and reopens nothing.
#   - THE FLAGS, WHOSE TURN IT IS AND WHAT IS UNREAD ARE DERIVED, NEVER STORED. A record holds what was
#     said, by whom, by what route, and the wording the speaker was looking at. Whether that wording
#     was already old, whether the question was closed, whose turn it now is and whether the other
#     side has read it all follow from the order of the records, and are worked out from it each time.
#   - A QUESTION'S THREAD IS ITS MESSAGES IN STORE ORDER. Two messages to one question are both there.
#
# A QUESTION'S NUMBER IS DERIVED FROM THE ORDER, AND IS PERMANENT. The Nth question-added record is
# question N; there is no counter anywhere. Each question-added record also carries the number it was
# given, as a CHECK on that derivation, and here is why it must. A record can become unreadable after
# it was written (a damaged disk, a file deleted by hand), and the reader cannot tell what kind it
# was. Counting only the readable question-added records would then renumber every question added
# after it - the shifting numbers this module exists to end. So:
#   - reading: a question-added record's own number is believed when it is ABOVE every number already
#     given. The numbers it jumps over belonged to records that cannot be read; they have no question,
#     and they are never given again. A record claiming a number at or below one already given
#     contradicts the order and is reported as unreadable; it changes nothing.
#   - writing: the next number is one above the highest given, PLUS one for every unreadable record
#     since the last readable question-added. Any of those may have been a question, so its number is
#     left unused. The cost is a gap in the numbers, which is harmless; the alternative is a number
#     that means two questions.
# With every record readable both rules reduce to "the Nth question-added is question N", and
# test/test-decisions-rules.ps1 holds them to that.
#
# THE COMPATIBILITY CONTRACT, FOR EVERY LATER EVENT KIND. A store outlives the version that wrote to
# it, and two versions may write to one store. So a record whose ENVELOPE is well formed - it matches
# schema/decision-event.v1, and says it is the record its place says - but whose KIND this version
# does not know is not damage. A later version wrote it. It is "not understood by this version":
#   - it is SET ASIDE from the fold: it changes no question, and is not reported as unreadable;
#   - it is REPORTED, once for its kind, with how many records and from which to which, in every
#     result, so nobody can show the list without saying that part of the store was not understood;
#   - IT NEVER COUNTS AS A POSSIBLE QUESTION, and so leaves no question number unused. This is safe
#     because of two promises every version makes: "question-added" is a kind every version knows,
#     and A KIND'S NAME NEVER CHANGES MEANING - a new meaning is a new name. A record of any other
#     name therefore cannot have added a question. Measured 2026-10-07, before this rule: one record
#     of a later kind between two questions numbered the next one 4 instead of 3, for good;
#   - ITS ID IS STILL SEEN: the envelope is readable, so a request sent again under that id is known
#     to have been recorded, and is not written a second time;
#   - ITS NUMBER STILL RAISES THE FLOOR. The two promises above hold only while a kind's NAME is
#     undamaged, and a damaged name can be another well-formed one: observed in review on 2026-10-07,
#     a question-added record with one letter of its kind changed was set aside, and its question
#     number was given to the next question. A number is never given twice, so a set-aside record whose
#     data has a "number" shaped like a question number (a whole number from 1 to the largest a
#     question may have) raises the floor: the next question is above it, and that number reads as
#     given and unreadable, not as never given. It only ever raises. For a record that really is of a
#     later kind this costs nothing: such a record names a question that already has its number, at
#     or below the floor - unless a later version adds questions under a new kind, when raising is
#     exactly right.
# What this asks of whoever adds a kind: never reuse a kind's name for another meaning; never make an
# existing kind's record mean something only together with a later kind's (an older version sees the
# first without the second); never give a later kind a data member named "number" that is anything but
# a question number, or this version raises its floor over it and hides questions the later version
# numbered; and keep the envelope as it is - a change to the envelope is a new
# schema version, which an older version reads as unreadable, with the conservative rule below.
# A RECORD THAT IS DAMAGED KEEPS THE CONSERVATIVE RULE: torn, missing, held, not this schema's
# envelope, out of its place, or of a KNOWN kind with data that is not that kind's. Any of those may
# have been a question, and each still leaves one number unused.
#
# STORED RECORDS ARE FACTS, NOT REQUESTS. The fold checks a record's SHAPE (its schemas) and whether it
# applies, never the wording rules below: a title rule tightened next month must not make last month's
# question unreadable. The wording rules are for what is about to be written.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Secrets.ps1")
. (Join-Path $PSScriptRoot "Format.ps1")

# THE EVENT KINDS. data: the definition of schema/decision-event.v1 its data must match. words: the
# member of its data, if any, that holds question fields (schema/decision-question.v1). apply: the
# function that applies it to the list, or returns why it cannot.
# about: "question" when its data names one question by number, "list" when it is about the whole
# list. actors: who may write it - "keepers" (the roles that keep the list, $HordeDecisionActors) or
# "speakers" (the roles that speak under a question, $HordeDecisionSpeakers). counts: the members of
# its data that are counts, each with the largest it may be, held here because the schema has no
# "maximum" (see THE LARGEST NUMBER below).
$script:HordeDecisionEventKinds = [ordered]@{
    "question-added"    = @{ data = "question-added";    words = "question"; apply = "Step-HordeDecisionAdded";    about = "question"; actors = "keepers";  counts = @{} }
    "question-updated"  = @{ data = "question-updated";  words = "changes";  apply = "Step-HordeDecisionUpdated";  about = "question"; actors = "keepers";  counts = @{} }
    "question-closed"   = @{ data = "question-closed";   words = "";         apply = "Step-HordeDecisionClosed";   about = "question"; actors = "keepers";  counts = @{} }
    "question-reopened" = @{ data = "question-reopened"; words = "";         apply = "Step-HordeDecisionReopened"; about = "question"; actors = "keepers";  counts = @{} }
    "message-said"      = @{ data = "message-said";      words = "";         apply = "Step-HordeDecisionSaid";     about = "question"; actors = "speakers"; counts = @{ wordingVersion = "number" } }
    "messages-read"     = @{ data = "messages-read";     words = "";         apply = "Step-HordeDecisionRead";     about = "list";     actors = "speakers"; counts = @{ upTo = "sequence" } }
}

# THE STATES a question can be in. A later slice adds to this list; nothing reads a state it does not
# find here except to show its name.
$script:HordeDecisionStates = @("open", "closed")

# WHO MAY WRITE to the list: role labels (core/roles.json names the roles), a closed list here beside
# the states and the event kinds. Today only the warchief writes. It is HERE and not an enum in
# schema/decision-event.v1 so that a second actor - the person answering - is one entry in this list
# and not a change to a schema that says it is version 1; and so that a record written under an actor
# this version does not list is still read. A stored record is a fact: the fold asks only that its
# actor is one lowercase label (the schema's pattern). Whether an actor MAY write is asked of a
# request, by decisions/Operations.ps1, before anything is written.
# THE ACTOR IS WHAT THE CALLER SAYS IT IS. Nothing here proves it; a caller across a link must have it
# set by the link, not taken from the request.
$script:HordeDecisionActors = @("warchief")

# WHO MAY SPEAK UNDER A QUESTION: a closed list. The founder is not a session role of core/roles.json:
# it is the person the list is kept for. shown: how a way of showing names the speaker. then: whose
# turn it is once this speaker has spoken under an open question. reads: whether this role has an
# inbox - whether "what it has not yet read" is kept track of. Today only the warchief does: the
# founder reads in a window that is a later unit, and until that window marks what he has seen,
# counting the warchief's replies as "unread by the founder" would be a number that means nothing.
# Giving the founder an inbox is turning that one flag on.
$script:HordeDecisionSpeakers = [ordered]@{
    founder  = @{ shown = "the founder";  then = "warchief"; reads = $false }
    warchief = @{ shown = "the warchief"; then = "founder";  reads = $true }
}
# WHOSE TURN IT IS, derived: the first speaker's when a question is asked or reopened (a question is
# asked OF the founder); the other speaker's once one has spoken; nobody's while it is closed.
$script:HordeDecisionFirstTurn = "founder"
$script:HordeDecisionNoTurn = "nobody"
# BY WHAT ROUTE WORDS ARRIVE: a closed list. speakers: whose words may arrive this way. actors: who may
# make the request that records them. shown: how a way of showing says it. statesWording: whether
# words by this route must say which wording of the question the speaker was looking at. The window
# knows what it showed, and always says; the session writing down what was said in chat does not
# know what was in front of the speaker, and a command has no screen. WHERE IT IS NOT STATED, NOTHING
# IS GUESSED: the record holds no wording, the message says "wording not stated", and "said to an
# earlier wording" is never worked out for it - that flag is only ever derived for a stated wording.
# "chat-recorded" IS ITS OWN ROUTE ON PURPOSE. The founder's words, typed by him into the window, and
# the founder's words as the warchief heard them in chat and wrote them down, are different evidence:
# the second passed through another hand. They are stored distinctly and shown distinctly, always.
$script:HordeDecisionRoutes = [ordered]@{
    "window"        = @{ speakers = @("founder");  actors = @("founder");  shown = "typed in the window";                statesWording = $true }
    "chat-recorded" = @{ speakers = @("founder");  actors = @("warchief"); shown = "recorded by the warchief from chat"; statesWording = $false }
    "command"       = @{ speakers = @("warchief"); actors = @("warchief"); shown = "by command";                         statesWording = $false }
    # "phone": the founder's answer from his phone, through the relay (relay design 2026-10-09, PR plan
    # item 5, and the founder's decision of the same day). The phone shows him the wording, so it always
    # states it, as the window does. His own caller records it - the relay channel, which has verified
    # his passkey's signature over the answer - so the actor is the founder, as for the window.
    # evidence: the route's words always carry the SHA-256, in lower-case hex, of the relay journal
    # record that proved them (relay/Journal.ps1 keeps the envelope whole, signature and all); no other
    # route's words may carry one. The proof itself stays in relay's journal: a decision record holds
    # only the hash, so this module never stores a signature, and never judges one - it cannot read the
    # journal, and is not the place that decides who signed. A route with no evidence member carries
    # none.
    # signedBy (2026-10-12): the key id of the passkey the relay channel verified the answer's envelope
    # against, written ONCE, here, by the caller that checked the signature - so that whoever tells the
    # warchief of the answer (decisions/Notify.ps1) names that passkey from the record and from nothing
    # else. Only a route that carries evidence may carry it; it is optional there, because records
    # written before it are facts too, and they name no passkey. It is the caller's word, like the
    # evidence: this module checks its spelling and its route, never who signed.
    "phone"         = @{ speakers = @("founder");  actors = @("founder");  shown = "answered on the founder's phone";    statesWording = $true; evidence = $true }
}
# THE EVIDENCE'S ONE SPELLING: a SHA-256 in lower-case hex. Never the proof, which is relay's to keep.
$script:HordeDecisionEvidencePattern = '\A[0-9a-f]{64}\z'
# THE SIGNING KEY'S ONE SPELLING: a relay key id, 32 lower-case hex (relay/Bytes.ps1).
$script:HordeDecisionSignedByPattern = '\A[0-9a-f]{32}\z'

# THE FIELDS OF A QUESTION, in the order they are stored and shown. type: text, list (of texts) or
# flag. oneLine: a line break is refused. wording: a change to it is a new wording, because it is what
# a person reads before answering - an answer given to wording 2 must not be taken as given to
# wording 3. The same names are schema/decision-question.v1's properties; the rules suite compares them.
$script:HordeDecisionFields = [ordered]@{
    title          = @{ type = "text"; oneLine = $true;  wording = $true }
    kind           = @{ type = "text"; oneLine = $true;  wording = $false }
    options        = @{ type = "list"; oneLine = $true;  wording = $true }
    parts          = @{ type = "list"; oneLine = $false; wording = $true }
    whatItIs       = @{ type = "text"; oneLine = $false; wording = $true }
    yesMeans       = @{ type = "text"; oneLine = $false; wording = $true }
    recommendation = @{ type = "text"; oneLine = $false; wording = $false }
    group          = @{ type = "text"; oneLine = $true;  wording = $false }
    groupNote      = @{ type = "text"; oneLine = $false; wording = $false }
    askedBy        = @{ type = "text"; oneLine = $true;  wording = $false }
    waiting        = @{ type = "list"; oneLine = $true;  wording = $false }
    files          = @{ type = "list"; oneLine = $true;  wording = $false }
    references     = @{ type = "list"; oneLine = $true;  wording = $false }
    needsSecret    = @{ type = "flag"; oneLine = $true;  wording = $false }
}
# The fields a new question must fill. whatItIs and yesMeans are "one of the two", checked on its own.
$script:HordeDecisionRequiredFields = @("title", "kind", "group", "askedBy")

# LIMITS. A text longer than the first is refused whole, with the count, never cut: 500,000 characters
# is five times the 100,000-character text the decisions design (2026-10-06, section 6) requires to be stored whole, and keeps a record
# under the 2,097,152 characters Windows PowerShell 5.1's ConvertFrom-Json will read back.
$script:HordeDecisionMaxTextChars = 500000
$script:HordeDecisionMaxLineChars = 1000
$script:HordeDecisionMaxListItems = 100
# THE LARGEST NUMBER A QUESTION AND A RECORD CAN HAVE. core/Schema.ps1 has no "maximum", and "type":
# "integer" passes 99999999999 and 1e30, so these are held here, for a stored record and a request
# alike. Measured 2026-10-06, before they were: ONE record numbered 99999999999 made list, show and
# add throw "Cannot convert value to type System.Int32" - the whole list unloadable for one record -
# and one numbered 2147483647 made every later add throw. A question's number is nine digits, which
# is what the command line takes (decisions/Console.ps1) and is inside the Int32 the list keeps it
# in. The largest a record's sequence number can be is NOT written here: it is the largest its file
# name can hold, and decisions/Format.ps1 is the one place that says how wide that name is. The
# rules ask it there (Get-HordeDecisionMaxSequence), as the store does.
$script:HordeDecisionMaxNumber = 999999999
# CHARACTERS THAT ARE NOT TEXT. A terminal obeys a control character, and a format or separator
# character changes how a line reads without being seen. Measured 2026-10-06, before these: a title
# holding ESC [2J and a group holding BEL were stored, and the plain-text list printed both raw; a
# line separator (U+2028) and a NUL sat in a "one line" title. Unicode's own categories are the
# list: Cc control, Cf format, Zl line separator, Zp paragraph separator. A one-line field takes
# none of them (CR and LF are left to the one-line rule, which names them better); a text of several
# lines takes CR, LF and tab and no other.
# FOUR FORMAT CHARACTERS ARE TEXT, AND ARE LEFT OUT OF THE REFUSAL: the direction marks U+200E and
# U+200F and the joiners U+200C and U+200D. Right-to-left text is written with the first two, and
# Persian, Indic scripts and joined emoji with the others; the design requires text in any alphabet
# to be stored exactly, and the operations suite's own Hebrew title carries U+200F. None of the four
# can reorder or hide other text. What reorders or hides IS refused: the embeddings, overrides and
# isolates (U+202A to U+202E, U+2066 to U+2069), the zero-width space, the byte-order mark.
# TWO CLASSES, DEFINED HERE AND NOWHERE ELSE, EACH NAMED FOR WHAT IT IS FOR. Both start from the same
# refusal - control, format, line-separator and paragraph-separator characters - and differ only in
# what of it they keep.
#   A QUESTION FIELD MUST NOT BE ABLE TO DISGUISE ITSELF. It is written by the session that keeps the
#     list, it is what a person reads before answering, and it can be written again. So it keeps
#     only what right-to-left and joined writing cannot do without: the two direction marks and the
#     two joiners (U+200C to U+200F). A character that reorders or hides the text beside it - an
#     embedding, an override, an isolate, a zero-width space - is refused.
#   A SPOKEN MESSAGE MUST BE STORED EXACTLY AS TYPED. What a person said cannot be written again, and
#     a phone's keyboard and a chat program put characters into right-to-left text that he never
#     sees: embeddings and overrides (U+202A to U+202E), isolates (U+2066 to U+2069), the Arabic
#     letter mark (U+061C), the zero-width space and the word joiner (U+200B, U+2060). Refusing
#     those would refuse his words, or make whoever records them take characters out. So a message
#     keeps them all - and says of itself that it holds such characters
#     (holdsDirectionOrInvisibleCharacters), so that whatever shows it knows to isolate it.
# BOTH still refuse a control character other than the line break (and, in more than a line, the
# tab), the byte-order mark (U+FEFF) and the line and paragraph separators (U+2028, U+2029): none is
# in anything a person typed, and the first is what a terminal obeys.
$script:HordeDecisionNotTextClasses = '\p{Cc}\p{Cf}\p{Zl}\p{Zp}'
$script:HordeDecisionQuestionFieldKeeps = '\r\n\u200C-\u200F'
$script:HordeDecisionSpokenMessageKeeps = '\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'
$script:HordeDecisionNotTextInOneLine = '[' + $script:HordeDecisionNotTextClasses + '-[' + $script:HordeDecisionQuestionFieldKeeps + ']]'
$script:HordeDecisionNotTextInLines = '[' + $script:HordeDecisionNotTextClasses + '-[\t' + $script:HordeDecisionQuestionFieldKeeps + ']]'
$script:HordeDecisionNotTextInWords = '[' + $script:HordeDecisionNotTextClasses + '-[' + $script:HordeDecisionSpokenMessageKeeps + ']]'
# WHAT A MESSAGE IS SAID TO HOLD when it holds any of them: every format character, and the three that
# older character tables do not yet call one.
$script:HordeDecisionDirectionOrInvisible = '[\p{Cf}\u061C\u2066-\u2069]'
# A title must have this many words besides numbers and reference words. "Merge PR 1469?" has one.
# In Chinese, Japanese, Thai, Lao, Khmer and Burmese a sentence is written with no spaces, so there
# each letter is counted as a word: about what one carries in Chinese, generous in the others.
$script:HordeDecisionUnspacedLetter = '[\p{IsCJKUnifiedIdeographs}\p{IsCJKUnifiedIdeographsExtensionA}\p{IsHiragana}\p{IsKatakana}\p{IsThai}\p{IsLao}\p{IsKhmer}\p{IsMyanmar}]'
$script:HordeDecisionMinTitleWords = 3

# WHAT LOOKS LIKE A SECRET is core/Secrets.ps1's to say (relay design 2026-10-09, PR plan item 9): the
# patterns, the thresholds and what they let through on purpose were lifted from here, unchanged, so the
# conversation port redacts exactly the shapes this module refuses. Find-HordeDecisionSecretKind below
# keeps its name for the callers and suites that use it, and only calls core; Find-HordeDecisionSecrets,
# the walk and its refusal wording, stays here.

function Get-HordeDecisionEventKinds { return @($script:HordeDecisionEventKinds.Keys) }
function Get-HordeDecisionSpeakers { return @($script:HordeDecisionSpeakers.Keys) }
function Get-HordeDecisionReaders { return @($script:HordeDecisionSpeakers.Keys | Where-Object { [bool]$script:HordeDecisionSpeakers[$_].reads }) }
function Get-HordeDecisionRoutes { return @($script:HordeDecisionRoutes.Keys) }

function Get-HordeDecisionKindAbout {
    # What an event kind is about: "question" (its data names one by number) or "list". "" for a kind
    # this version does not know.
    param([string]$Kind)
    $entry = $script:HordeDecisionEventKinds[$Kind]
    if ($null -eq $entry) { return "" }
    return "$($entry.about)"
}

function Get-HordeDecisionKindActors {
    # Who may write an event of -Kind, as { roles; may }: the role labels, and what they may do, in
    # words for a refusal. Asked of a request before it is written; a stored record is a fact and is
    # not asked this.
    param([Parameter(Mandatory = $true)][string]$Kind)
    $entry = $script:HordeDecisionEventKinds[$Kind]
    if ($null -ne $entry -and "$($entry.actors)" -ceq "speakers") { return [pscustomobject]@{ roles = @($script:HordeDecisionSpeakers.Keys); may = "speak under a question, or mark what was said there as read" } }
    return [pscustomobject]@{ roles = @($script:HordeDecisionActors); may = "change the list" }
}

function Get-HordeDecisionSpeakerShown {
    # How a speaker is named to a person. A label this version does not list (a later version wrote
    # it) is shown as it is.
    param([string]$Speaker)
    $entry = $script:HordeDecisionSpeakers[$Speaker]
    if ($null -eq $entry) { return $Speaker }
    return "$($entry.shown)"
}

function Get-HordeDecisionSigner {
    # The passkey a message's record names as the one that signed it: { keyId; why }. keyId is "" when
    # the record names none that may be repeated, and why says so in words. THE ONE PLACE THAT READS A
    # RECORD'S signedBy FOR A CLAIM: it counts only on a route that carries evidence (the route phone),
    # beside evidence spelled as evidence, and spelled as a key id - so a record by any other route that
    # holds the member, however it came to, names nobody. It says what the record says, never whether
    # that passkey is trusted: that is relay's trust store's to answer, and the asker's to ask.
    param([string]$Route, [string]$Evidence = "", [string]$SignedBy = "")
    $none = { param([string]$Why) return [pscustomobject]@{ keyId = ""; why = $Why } }
    $entry = $script:HordeDecisionRoutes[$Route]
    if ($null -eq $entry -or -not ($entry.ContainsKey("evidence") -and [bool]$entry.evidence)) { return (& $none ("they were " + (Get-HordeDecisionRouteShown -Route $Route) + ", and no passkey signs words by that route")) }
    if ($Evidence -cnotmatch $script:HordeDecisionEvidencePattern) { return (& $none "their record holds no evidence of the proof") }
    if ($SignedBy -ceq "") { return (& $none "their record names no passkey: it was written before records did") }
    if ($SignedBy -cnotmatch $script:HordeDecisionSignedByPattern) { return (& $none "what their record names as the passkey is not a key id") }
    return [pscustomobject]@{ keyId = $SignedBy; why = "" }
}

function Get-HordeDecisionRouteShown {
    param([string]$Route)
    $entry = $script:HordeDecisionRoutes[$Route]
    if ($null -eq $entry) { return $Route }
    return "$($entry.shown)"
}
function Get-HordeDecisionStates { return @($script:HordeDecisionStates) }
function Get-HordeDecisionActors { return @($script:HordeDecisionActors) }
function Get-HordeDecisionFieldNames { return @($script:HordeDecisionFields.Keys) }
function Get-HordeDecisionMaxNumber { return $script:HordeDecisionMaxNumber }

function Test-HordeDecisionCount {
    # Is a value a whole number from 1 to -Most? Compared as a Double and NEVER CAST FIRST: 1e30 is an
    # integer to the schema, and casting it to a 32- or 64-bit number is the throw this guards against.
    # Every limit here is far below 2^53, so the comparison is exact.
    param($Value, [Parameter(Mandatory = $true)][double]$Most)
    if (-not (Test-HordeSchemaType -Value $Value -Type "integer")) { return $false }
    $size = [double]$Value
    return ($size -ge 1 -and $size -le $Most)
}

function Test-HordeDecisionMember {
    # Does a parsed JSON object, or a table built here, have the member? Asked, never assumed: under
    # strict mode reading a property that is not there throws.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return [bool]$Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Get-HordeDecisionMember {
    # The member's value, or $null when there is none. Returned with the unary comma so a list keeps
    # its shape - a list of one would otherwise arrive as its one item (core/Tristate.ps1, L-004).
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return ,$Object[$Name] }; return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return ,$prop.Value
}

function ConvertTo-HordeDecisionCanonicalText {
    # One text for one value, whatever order its keys were given in, for hashing only: nothing parses
    # it. Keys are sorted by ordinal comparison; a whole number has one spelling whatever .NET type
    # holds it (Windows PowerShell 5.1's ConvertFrom-Json reads 1.0 as a Decimal). Anything that is
    # not JSON data is refused, never turned into its type name.
    # remote/Journal.ps1 has a fuller form of the same idea for the link's request ids. It is not
    # loaded here: the decisions rules would then depend on the link's code to hash a question.
    param($Value)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return "null" }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [string]) { return ('"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"') }
    if (Test-HordeSchemaIsNumber $Value) {
        if (-not (Test-HordeSchemaType -Value $Value -Type "integer")) { throw ("the number " + $Value + " cannot be hashed: only whole numbers are decisions data") }
        return ([long]$Value).ToString($inv)
    }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        $map = Get-HordeObjectByKey $Value
        $sorted = [string[]]@($map.Keys)
        [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $pairs = foreach ($k in $sorted) { (ConvertTo-HordeDecisionCanonicalText -Value $k) + ":" + (ConvertTo-HordeDecisionCanonicalText -Value $map[$k]) }
        return ("{" + (@($pairs) -join ",") + "}")
    }
    if ($Value -is [System.Collections.IList]) {
        $items = foreach ($item in $Value) { ConvertTo-HordeDecisionCanonicalText -Value $item }
        return ("[" + (@($items) -join ",") + "]")
    }
    throw ("a value of type " + $Value.GetType().FullName + " cannot be hashed: only JSON data can")
}

function Get-HordeDecisionHash {
    # SHA-256, lowercase hex, of a value's canonical text in UTF-8.
    param($Value)
    $text = ConvertTo-HordeDecisionCanonicalText -Value $Value
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $digest) { [void]$sb.Append($b.ToString("x2")) }
    return $sb.ToString()
}

function Find-HordeDecisionSecretKind {
    # What kind of secret a text looks like it holds, as words for a finding, or "" for none:
    # core/Secrets.ps1's one list.
    param([string]$Text)
    return (Find-HordeSecretKind -Text $Text)
}

function Find-HordeDecisionSecrets {
    # A finding for every text anywhere in a value that looks like a secret. THE FINDING NAMES THE
    # FIELD AND THE KIND OF SECRET, AND NEVER THE VALUE: a refusal is printed, logged and may travel,
    # and repeating the secret in it would be the leak the check exists to stop. Every text is
    # looked at, in whatever member it sits, and so is every member's NAME, so a field or an event
    # kind added later is covered without being listed here.
    param($Value, [string]$Path = "the request")
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [string]) {
        $kind = Find-HordeDecisionSecretKind -Text $Value
        if ($kind -ne "") { [void]$out.Add($Path + " holds what looks like " + $kind + ". A secret is never stored in the list: leave it out, and mark the question needsSecret if answering needs one") }
    }
    elseif ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        $map = Get-HordeObjectByKey $Value
        foreach ($k in @($map.Keys)) {
            # A NAME IS TEXT TOO, and the schema's finding for a member it does not allow repeats the
            # name: a token pasted where a field's name goes came back in the refusal (measured
            # 2026-10-06). So a name is looked at like any text, and one that looks like a secret is
            # never used to say where anything is.
            $where = "'" + $k + "'"
            $nameKind = Find-HordeDecisionSecretKind -Text "$k"
            if ($nameKind -ne "") {
                $where = "a field whose name is not repeated here"
                [void]$out.Add("a field name in " + $Path + " holds what looks like " + $nameKind + ". A secret is never stored in the list: leave it out, and mark the question needsSecret if answering needs one")
            }
            foreach ($f in @(Find-HordeDecisionSecrets -Value $map[$k] -Path $where)) { [void]$out.Add($f) }
        }
    }
    elseif ($Value -is [System.Collections.IList]) {
        $i = 0
        foreach ($item in $Value) { $i++; foreach ($f in @(Find-HordeDecisionSecrets -Value $item -Path ($Path + " (item " + $i + ")"))) { [void]$out.Add($f) } }
    }
    return @($out)
}

function ConvertTo-HordeDecisionFields {
    # A question's fields from a value that has passed schema/decision-question.v1, as an ordered
    # table in the one field order, each value of its one .NET type. Without -Partial every field is
    # there, an absent one as its empty value ("", no items, false); with it, only the fields given,
    # which is what a change is. Texts are kept exactly: nothing is trimmed or re-encoded.
    param($Source, [switch]$Partial)
    $out = [ordered]@{}
    foreach ($name in $script:HordeDecisionFields.Keys) {
        $type = $script:HordeDecisionFields[$name].type
        $given = Test-HordeDecisionMember -Object $Source -Name $name
        if (-not $given -and $Partial) { continue }
        $raw = $null
        if ($given) { $raw = Get-HordeDecisionMember -Object $Source -Name $name }
        if ($type -eq "list") {
            $items = New-Object 'System.Collections.Generic.List[string]'
            if ($null -ne $raw) { foreach ($item in @($raw)) { $items.Add([string]$item) } }
            $out[$name] = $items.ToArray()
        }
        elseif ($type -eq "flag") { $out[$name] = ($raw -eq $true) }
        else { if ($null -eq $raw) { $out[$name] = "" } else { $out[$name] = [string]$raw } }
    }
    return $out
}

function Get-HordeDecisionCharProblem {
    # Why a text holds something that is not text, as the end of a finding ("holds the character
    # U+001B ..."), or "". Only the first such character is named. The text is never cleaned: what is
    # stored is what was given, so what cannot be stored is refused whole.
    param([string]$Text, [switch]$OneLine, [switch]$Said)
    $pattern = $script:HordeDecisionNotTextInLines
    $takes = "a text of several lines takes line breaks and tabs, and no other control, format or separator character"
    if ($Said) {
        $pattern = $script:HordeDecisionNotTextInWords
        $takes = "words said under a question are kept exactly as typed, direction characters included; they take no control character but the line break and the tab, no byte-order mark, and no line or paragraph separator"
    }
    if ($OneLine) {
        $pattern = $script:HordeDecisionNotTextInOneLine
        $takes = "a one-line field takes no control, format or separator character, a tab included"
    }
    $hit = [regex]::Match($Text, $pattern)
    if (-not $hit.Success) { return "" }
    $code = [int][char]$hit.Value
    $sort = "a control character"
    $category = [System.Char]::GetUnicodeCategory([char]$code)
    if ($category -eq [System.Globalization.UnicodeCategory]::Format) { $sort = "an invisible format character" }
    elseif ($category -eq [System.Globalization.UnicodeCategory]::LineSeparator) { $sort = "a line separator" }
    elseif ($category -eq [System.Globalization.UnicodeCategory]::ParagraphSeparator) { $sort = "a paragraph separator" }
    return ("holds the character U+" + $code.ToString("X4") + ", " + $sort + ". It is refused, not removed: " + $takes)
}

function Get-HordeDecisionTitleProblem {
    # Why a title does not explain itself, or "". The rule this builds in: a person reading only the
    # title, with no other context, must understand what is asked. A number or a pull-request or issue
    # reference names something the reader has to look up, so those, and the words that only introduce
    # them, do not count as saying anything.
    param([string]$Title)
    if ($Title -notmatch '\p{L}') { return "the title has no letters: write the question in plain words" }
    # A LINK IS A REFERENCE, whatever words its host and path are made of: before links were set
    # aside, a title that was only a pull request's address counted six words and was added (measured
    # 2026-10-06).
    $rest = [regex]::Replace($Title, '(?i)\b[a-z][a-z0-9+.-]*://\S+', ' ')
    # "Not followed by a letter", not \b: there is no word boundary between a letter and a digit, so
    # with \b "PR1469" kept its "PR" as a word, and "PR1469 PR1470 PR1471" was added as three (same
    # measurement). "press" and "bugfix" are still words: a letter follows.
    $rest = [regex]::Replace($rest, '(?i)\b(pull[\s-]*requests?|prs?|merge[\s-]*requests?|mrs?|issues?|tickets?|bugs?)(?!\p{L})', ' ')
    $rest = [regex]::Replace($rest, '#?[0-9]+', ' ')
    # A letter of a script that writes no spaces between words counts as a word by itself; a run of any
    # other letters is one word. Measured 2026-10-06, before this: a Chinese sentence of eleven
    # characters was refused as one word.
    $words = [regex]::Matches($rest, ($script:HordeDecisionUnspacedLetter + '|\p{L}[\p{L}\p{M}]*')).Count
    if ($words -eq 0) { return "the title is only a pull-request or issue reference: write the question in plain words, and put the reference in 'references'" }
    if ($words -lt $script:HordeDecisionMinTitleWords) {
        return ("the title is too short to explain itself: besides numbers and references it has " + $words + " word(s), and it needs at least " + $script:HordeDecisionMinTitleWords + ". Write the question so that someone with no other context understands it")
    }
    return ""
}

function Test-HordeDecisionQuestion {
    # Findings for a whole question that is about to be written: -Question is every field
    # (ConvertTo-HordeDecisionFields, or a question of the list), -Kinds the question-kind table.
    # Empty means it may be written. Secrets are not looked for here: Find-HordeDecisionSecrets runs
    # over the whole request first, so that no later finding can repeat one.
    param($Question, $Kinds)
    $out = New-Object System.Collections.ArrayList
    foreach ($name in $script:HordeDecisionFields.Keys) {
        $spec = $script:HordeDecisionFields[$name]
        $value = Get-HordeDecisionMember -Object $Question -Name $name
        if ($spec.type -eq "flag") { continue }
        $texts = @($value)
        if ($spec.type -eq "list" -and $texts.Count -gt $script:HordeDecisionMaxListItems) { [void]$out.Add("'" + $name + "' has " + $texts.Count + " items; the most is " + $script:HordeDecisionMaxListItems) }
        $i = 0
        foreach ($text in $texts) {
            $i++
            $where = "'" + $name + "'"
            if ($spec.type -eq "list") {
                $where = $where + " (item " + $i + ")"
                if ("$text".Trim() -eq "") { [void]$out.Add($where + " is blank") }
            }
            $most = $script:HordeDecisionMaxTextChars
            if ($spec.oneLine) {
                $most = $script:HordeDecisionMaxLineChars
                if ("$text" -match "[\r\n]") { [void]$out.Add($where + " must be one line, and it has a line break") }
            }
            if ("$text".Length -gt $most) { [void]$out.Add($where + " is " + "$text".Length + " characters long; the most is " + $most + ". It is refused whole, never cut") }
            $notText = Get-HordeDecisionCharProblem -Text "$text" -OneLine:([bool]$spec.oneLine)
            if ($notText -ne "") { [void]$out.Add($where + " " + $notText) }
        }
    }
    foreach ($name in $script:HordeDecisionRequiredFields) {
        if ("$(Get-HordeDecisionMember -Object $Question -Name $name)".Trim() -eq "") { [void]$out.Add("'" + $name + "' is missing or blank") }
    }
    $title = "$(Get-HordeDecisionMember -Object $Question -Name 'title')"
    if ($title.Trim() -ne "") { $why = Get-HordeDecisionTitleProblem -Title $title; if ($why -ne "") { [void]$out.Add($why) } }
    if ("$(Get-HordeDecisionMember -Object $Question -Name 'whatItIs')".Trim() -eq "" -and "$(Get-HordeDecisionMember -Object $Question -Name 'yesMeans')".Trim() -eq "") {
        [void]$out.Add("a question must explain itself: give 'whatItIs' (the background) or 'yesMeans' (what a yes would do), or both")
    }
    $kind = "$(Get-HordeDecisionMember -Object $Question -Name 'kind')"
    if ($kind.Trim() -ne "") {
        if (-not (Test-HordeDecisionMember -Object $Kinds -Name $kind)) {
            [void]$out.Add("'kind' is '" + $kind + "', which is not a kind of question; the kinds are: " + ((Get-HordeObjectByKey $Kinds).Keys -join ", "))
        } else {
            $needs = "$((Get-HordeDecisionMember -Object $Kinds -Name $kind).list)"
            foreach ($listName in @("options", "parts")) {
                # Assigned, then wrapped: the member comes back with the unary comma, so wrapping the
                # call itself would make a list of one holding the whole list (core/Tristate.ps1).
                $held = Get-HordeDecisionMember -Object $Question -Name $listName
                $items = @($held)
                if ($listName -eq $needs) {
                    if ($items.Count -lt 2) { [void]$out.Add("a question of kind " + $kind + " needs at least two " + $listName + ", and this has " + $items.Count) }
                    $distinct = @($items | Sort-Object -Unique)
                    if ($distinct.Count -ne $items.Count) { [void]$out.Add("'" + $listName + "' names one item twice") }
                }
                elseif ($items.Count -gt 0) { [void]$out.Add("'" + $listName + "' is given, but a question of kind " + $kind + " has none; it would be stored and never shown") }
            }
        }
    }
    return @($out)
}

function Test-HordeDecisionNote {
    # Findings for a text that goes with an act on a question - the outcome it is closed with, the
    # reason it is reopened for. -Name is how a finding names it. It must say something, and it is
    # held to the same lengths as a question's own texts.
    param([string]$Text, [Parameter(Mandatory = $true)][string]$Name, [switch]$OneLine)
    $out = New-Object System.Collections.ArrayList
    if ($Text.Trim() -eq "") { [void]$out.Add("'" + $Name + "' is blank: say it in plain words") }
    $most = $script:HordeDecisionMaxTextChars
    if ($OneLine) {
        $most = $script:HordeDecisionMaxLineChars
        if ($Text -match "[\r\n]") { [void]$out.Add("'" + $Name + "' must be one line, and it has a line break") }
    }
    if ($Text.Length -gt $most) { [void]$out.Add("'" + $Name + "' is " + $Text.Length + " characters long; the most is " + $most + ". It is refused whole, never cut") }
    $unfit = Get-HordeDecisionCharProblem -Text $Text -OneLine:$OneLine
    if ($unfit -ne "") { [void]$out.Add("'" + $Name + "' " + $unfit) }
    return @($out)
}

function Test-HordeDecisionSaying {
    # Findings for words about to be recorded under a question: who is said to have spoken, by what
    # route, who is making the request, and the words. Empty means they may be written. THE TEXT IS
    # NEVER REPEATED in a finding, and never changed: what cannot be stored is refused whole.
    # Secrets are not looked for here: Find-HordeDecisionSecrets runs over the whole request first.
    # -EvidenceStated says whether the request carries evidence at all, and -Evidence what it is: a
    # [string] cannot hold "not given" (CONTRIBUTING 12), and "given, but empty" is a wrong value.
    # -SignedByStated and -SignedBy likewise, for the key id of the passkey that signed (the route phone).
    param([string]$Speaker, [string]$Route, [string]$Actor, [string]$Text, [bool]$WordingStated = $true, [bool]$EvidenceStated = $false, [string]$Evidence = "", [bool]$SignedByStated = $false, [string]$SignedBy = "")
    $out = New-Object System.Collections.ArrayList
    $speakerKnown = $script:HordeDecisionSpeakers.Contains($Speaker)
    $routeEntry = $script:HordeDecisionRoutes[$Route]
    if (-not $speakerKnown) { [void]$out.Add("'speaker' is '" + $Speaker + "', which is not someone who speaks under a question; the speakers are: " + (@($script:HordeDecisionSpeakers.Keys) -join ", ")) }
    if ($null -eq $routeEntry) { [void]$out.Add("'route' is '" + $Route + "', which is not a way words arrive; the routes are: " + (@($script:HordeDecisionRoutes.Keys) -join ", ")) }
    if ($speakerKnown -and $null -ne $routeEntry) {
        if (@($routeEntry.speakers) -cnotcontains $Speaker) { [void]$out.Add("words " + $routeEntry.shown + " are never " + $script:HordeDecisionSpeakers[$Speaker].shown + "'s: by the route '" + $Route + "' only these speak: " + (@($routeEntry.speakers) -join ", ")) }
        if (@($routeEntry.actors) -cnotcontains $Actor) { [void]$out.Add("words " + $routeEntry.shown + " are recorded only by: " + (@($routeEntry.actors) -join ", ") + ". The request came from '" + $Actor + "'") }
        if ([bool]$routeEntry.statesWording -and -not $WordingStated) { [void]$out.Add("words " + $routeEntry.shown + " always say which wording of the question was on screen ('wordingVersion'), and these do not") }
        $needsEvidence = ($routeEntry.ContainsKey("evidence") -and [bool]$routeEntry.evidence)
        if ($needsEvidence -and -not $EvidenceStated) { [void]$out.Add("words " + $routeEntry.shown + " always carry the hash of the proof that they came from the speaker ('evidence'), and these do not") }
        if (-not $needsEvidence -and $EvidenceStated) { [void]$out.Add("words " + $routeEntry.shown + " carry no 'evidence': only words answered on the founder's phone do") }
        if (-not $needsEvidence -and $SignedByStated) { [void]$out.Add("words " + $routeEntry.shown + " carry no 'signedBy': no passkey signed them, and only words answered on the founder's phone name one") }
    }
    # Its spelling, whatever the route: the request's schema says the same, and this is what a caller
    # that reaches the rules without it is held to.
    if ($EvidenceStated -and $Evidence -cnotmatch $script:HordeDecisionEvidencePattern) { [void]$out.Add("'evidence' is not a SHA-256 in lower-case hex: 64 of 0-9 and a-f") }
    if ($SignedByStated -and $SignedBy -cnotmatch $script:HordeDecisionSignedByPattern) { [void]$out.Add("'signedBy' is not a key id: 32 of 0-9 and a-f, in lower case") }
    if ($Text.Trim().Length -eq 0) { [void]$out.Add("'text' is blank: nothing was said") }
    if ($Text.Length -gt $script:HordeDecisionMaxTextChars) { [void]$out.Add("'text' is " + $Text.Length + " characters long; the most is " + $script:HordeDecisionMaxTextChars + ". It is refused whole, never cut") }
    $notWords = Get-HordeDecisionCharProblem -Text $Text -Said
    if ($notWords -ne "") { [void]$out.Add("'text' " + $notWords) }
    return @($out)
}

function New-HordeDecisionState {
    # The list before any record: nothing asked. questions is keyed by number and kept in number order.
    return [pscustomobject]@{
        questions = (New-Object 'System.Collections.Generic.SortedDictionary[int,object]')
        lastNumber = 0
        pending = 0
        ids = (New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal))
        unreadable = (New-Object System.Collections.ArrayList)
        ignored = (New-Object System.Collections.ArrayList)
        # Files the store would not believe were records. The rules do nothing with them: they are
        # carried here so that every result worked out from this list can name them.
        strays = (New-Object System.Collections.ArrayList)
        # Records of a kind this version does not know (see THE COMPATIBILITY CONTRACT), by kind, in
        # the order each kind was first met: { kind; count; first; last }, first and last being
        # sequence numbers.
        notUnderstood = (New-Object System.Collections.Specialized.OrderedDictionary)
        lastSequence = [long]0
        # How far each reader has read what others said: role label -> the sequence number of the
        # last record it has read up to. A reader with no entry has read nothing.
        readMarks = (New-Object 'System.Collections.Generic.Dictionary[string,long]' ([System.StringComparer]::Ordinal))
        # Every messages-read record that applied, by its own sequence number, as { reader; from; upTo }:
        # from is how far that reader had read before it. A repost of the request that made it is
        # answered with the same messages from this.
        readEvents = (New-Object 'System.Collections.Generic.Dictionary[long,object]')
    }
}

function Get-HordeDecisionNextNumber {
    # The number a question added now would get: one above the highest given, plus one for every
    # unreadable record since the last readable question-added (see the header).
    param($State)
    return ([int]$State.lastNumber + [int]$State.pending + 1)
}

function Get-HordeDecisionNumberStatus {
    # What the list knows of one number: present (a question), unreadable (the number was given, or
    # may have been, to a record that cannot be read), or absent (never given).
    param($State, [int]$Number)
    if ($State.questions.ContainsKey($Number)) { return "present" }
    if ($Number -ge 1 -and $Number -le ([int]$State.lastNumber + [int]$State.pending)) { return "unreadable" }
    return "absent"
}

function Add-HordeDecisionHistory {
    param($Question, $Ev, [string]$Note)
    [void]$Question.history.Add([pscustomobject]@{ sequence = [long]$Ev.sequence; kind = "$($Ev.kind)"; at = "$($Ev.at)"; actor = "$($Ev.actor)"; note = $Note })
    $Question.updatedAt = "$($Ev.at)"
}

function Step-HordeDecisionAdded {
    param($State, $Ev)
    $number = [int]$Ev.data.number
    if ($number -le [int]$State.lastNumber) {
        # Counted as pending: it may be a real question whose number was damaged, and the next
        # question written must not take a number this one might have had.
        $State.pending = [int]$State.pending + 1
        return ("it says it is question " + $number + ", but numbers up to " + $State.lastNumber + " were already given by earlier records; a number is never given twice, so it is not shown")
    }
    # A number above the next one is believed: the numbers jumped over stay unused (see the header).
    $question = ConvertTo-HordeDecisionFields -Source $Ev.data.question
    $question["number"] = $number
    $question["state"] = "open"
    $question["wordingVersion"] = 1
    $question["outcome"] = ""
    $question["reopenReason"] = ""
    $question["addedAt"] = "$($Ev.at)"
    $question["updatedAt"] = "$($Ev.at)"
    $question["closedAt"] = ""
    $question["history"] = (New-Object System.Collections.ArrayList)
    $question["thread"] = (New-Object System.Collections.ArrayList)
    $question["turn"] = $script:HordeDecisionFirstTurn
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "added"
    $State.questions[$number] = $question
    $State.lastNumber = $number
    $State.pending = 0
    return ""
}

function Get-HordeDecisionTarget {
    # The question a record is about, as { question; why }: why says what is wrong when there is none.
    param($State, $Ev)
    $about = [int]$Ev.data.number
    if ($State.questions.ContainsKey($about)) { return [pscustomobject]@{ question = $State.questions[$about]; why = "" } }
    if ((Get-HordeDecisionNumberStatus -State $State -Number $about) -eq "unreadable") {
        return [pscustomobject]@{ question = $null; why = ("it is about question " + $about + ", whose own record cannot be read") }
    }
    return [pscustomobject]@{ question = $null; why = ("it is about question " + $about + ", and there is no question " + $about) }
}

function Step-HordeDecisionUpdated {
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    if ($question.state -cne "open") { return ("question " + $question.number + " is " + $question.state + ", and only an open question can be changed; reopen it first") }
    $changes = ConvertTo-HordeDecisionFields -Source $Ev.data.changes -Partial
    $changed = New-Object System.Collections.ArrayList
    $reworded = $false
    foreach ($name in @($changes.Keys)) {
        if ((ConvertTo-HordeDecisionCanonicalText -Value $question[$name]) -ceq (ConvertTo-HordeDecisionCanonicalText -Value $changes[$name])) { continue }
        $question[$name] = $changes[$name]
        [void]$changed.Add($name)
        if ($script:HordeDecisionFields[$name].wording) { $reworded = $true }
    }
    if ($changed.Count -eq 0) { return ("it changes nothing: every field it names already has that value in question " + $question.number) }
    $note = "changed " + ($changed -join ", ")
    if ($reworded) { $question.wordingVersion = [int]$question.wordingVersion + 1; $note = $note + " (now wording " + $question.wordingVersion + ")" }
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note $note
    return ""
}

function Step-HordeDecisionClosed {
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    if ($question.state -cne "open") { return ("question " + $question.number + " is already " + $question.state) }
    $question.state = "closed"
    $question.outcome = "$($Ev.data.outcome)"
    $question.closedAt = "$($Ev.at)"
    # Closing ends whoever's turn it was: nothing is waited for under a closed question.
    $question.turn = $script:HordeDecisionNoTurn
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "closed"
    return ""
}

function Step-HordeDecisionReopened {
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    if ($question.state -cne "closed") { return ("question " + $question.number + " is " + $question.state + ", and only a closed question can be reopened") }
    # The number, the wording version and the history stay: a reopened question is the same question.
    # The outcome it was closed with is in the history's record, not carried on an open question.
    $question.state = "open"
    $question.outcome = ""
    $question.closedAt = ""
    $question.reopenReason = "$($Ev.data.reason)"
    # A reopened question is asked again, of the same person: whatever was said while it was closed
    # is in its thread, and did not take a turn.
    $question.turn = $script:HordeDecisionFirstTurn
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "reopened"
    return ""
}

function Test-HordeDecisionEnvelope {
    # Findings for a parsed record's ENVELOPE alone: that it matches schema/decision-event.v1 and its
    # sequence number is one a record can have. Nothing is asked of its kind or its data. Empty means
    # the envelope can be trusted: its sequence, its id and its kind's NAME are what they say.
    param($Ev, $Definitions)
    $found = @(Test-HordeSchema -Value $Ev -Schema $Definitions.eventSchema)
    if ($found.Count -gt 0) { return @("it is not a decision-event.v1 record: " + (@($found | Select-Object -First 3) -join "; ")) }
    if (-not (Test-HordeDecisionCount -Value $Ev.sequence -Most (Get-HordeDecisionMaxSequence))) { return @("its sequence number is beyond " + (Get-HordeDecisionMaxSequence) + ", the largest a record can have") }
    return @()
}

# WHO MAY MARK WORDS AS A NOTE OR AS AN ACT (decisions/Operations.ps1 says why). A note is the
# keeper's: words to the founder that ask him nothing. An act is the founder's, typed in the window.
$script:HordeDecisionNoteSpeakers = @("warchief")
$script:HordeDecisionActRoutes = @("window")
$script:HordeDecisionActs = @("park", "unpark")

function Test-HordeDecisionSayMarks {
    # Findings for a say request's asks and act (above): empty when both are absent or allowed.
    param($Request, [string]$Speaker, [string]$Route)
    $found = New-Object System.Collections.ArrayList
    if (Test-HordeDecisionMember -Object $Request -Name "asks") {
        if ($Request.asks -isnot [bool]) { [void]$found.Add("'asks' is true or false") }
        elseif ($Request.asks -eq $false -and $script:HordeDecisionNoteSpeakers -cnotcontains $Speaker) { [void]$found.Add("only the words of " + (@($script:HordeDecisionNoteSpeakers | ForEach-Object { Get-HordeDecisionSpeakerShown -Speaker $_ }) -join " or ") + " can be a note that asks nothing") }
    }
    if (Test-HordeDecisionMember -Object $Request -Name "act") {
        if ($script:HordeDecisionActs -cnotcontains [string]$Request.act) { [void]$found.Add("'act' is one of: " + ($script:HordeDecisionActs -join ", ")) }
        elseif ($Speaker -cne $script:HordeDecisionFirstTurn -or $script:HordeDecisionActRoutes -cnotcontains $Route) { [void]$found.Add("an act is recorded only for the founder's words typed in the window") }
    }
    return @($found)
}

function Step-HordeDecisionSaid {
    # Someone said something under a question. The words are added to the question's thread, in store
    # order, and NOTHING ELSE of the question changes: not its number, its wording, its state, its
    # history or when it was last changed. Under a closed question they are kept all the same, and
    # reopen nothing. That they arrived after closing, and that they were said to a wording the
    # question had already left, are both worked out HERE, from where the record stands in the order:
    # facts about the moment, which no later record undoes or adds. The record itself holds only the
    # wording its speaker was looking at.
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    # The wording the speaker was looking at, when the record states one. When it does not, nothing is
    # put in its place: 0 here means "not stated", and is never compared with anything.
    $stated = Test-HordeDecisionMember -Object $Ev.data -Name "wordingVersion"
    $seen = 0
    if ($stated) { $seen = [int]$Ev.data.wordingVersion }
    if ($stated -and $seen -gt [int]$question.wordingVersion) {
        return ("it says it was said to wording " + $seen + " of question " + $question.number + ", which has only reached wording " + $question.wordingVersion + ": nobody can have been looking at a wording that was not written yet")
    }
    $speaker = "$($Ev.data.speaker)"
    [void]$question.thread.Add([pscustomobject]@{
        sequence = [long]$Ev.sequence; at = "$($Ev.at)"; speaker = $speaker; route = "$($Ev.data.route)"; recordedBy = "$($Ev.actor)"
        # Exactly what the record holds: never trimmed, never re-wrapped.
        text = [string]$Ev.data.text
        wordingStated = [bool]$stated
        wordingVersion = $seen
        saidToEarlierWording = [bool]($stated -and $seen -lt [int]$question.wordingVersion)
        arrivedAfterClosing = [bool]($question.state -cne "open")
        # A note (asks false) and an act, as the record holds them (Test-HordeDecisionSayMarks).
        asks = [bool](-not ((Test-HordeDecisionMember -Object $Ev.data -Name "asks") -and $Ev.data.asks -eq $false))
        act = $(if (Test-HordeDecisionMember -Object $Ev.data -Name "act") { [string]$Ev.data.act } else { "" })
        # The hash of the proof (the route phone), as the record holds it; "" when it holds none. A stored
        # record is a fact: one by the route phone without evidence is read, and shows none.
        evidence = $(if (Test-HordeDecisionMember -Object $Ev.data -Name "evidence") { [string]$Ev.data.evidence } else { "" })
        # The key id of the passkey that signed (the route phone), as the record holds it; "" when it
        # names none - every record written before 2026-10-12, and every other route's.
        signedBy = $(if (Test-HordeDecisionMember -Object $Ev.data -Name "signedBy") { [string]$Ev.data.signedBy } else { "" })
    })
    $last = $question.thread[$question.thread.Count - 1]
    # AN EDIT (the owner, 2026-10-07): words of the same speaker straight after their own last
    # words under the question - acts left aside - replace them. Worked out here, at the record's place.
    $replaces = $false
    if ($last.act -eq "") {
        for ($i = $question.thread.Count - 2; $i -ge 0; $i--) {
            $before = $question.thread[$i]
            if ("$($before.act)" -ne "") { continue }
            $replaces = ("$($before.speaker)" -ceq $speaker)
            break
        }
    }
    Add-Member -InputObject $last -NotePropertyName replaces -NotePropertyValue ([bool]$replaces)
    # The turn passes only under an open question, only for a speaker this version lists, and not on
    # words that ask nothing (a note) or that record an act.
    if ($question.state -ceq "open" -and $script:HordeDecisionSpeakers.Contains($speaker) -and $last.asks -and $last.act -eq "") { $question.turn = "$($script:HordeDecisionSpeakers[$speaker].then)" }
    return ""
}

function Step-HordeDecisionRead {
    # A reader has read what others said, up to a record. It moves that reader's mark forward and
    # changes nothing else. A mark that moves nothing - the reader had already read that far - does
    # not apply, so the same marking sent twice is one marking; and a mark that claims a record at or
    # after its own place is refused, because nothing is read before it is written.
    param($State, $Ev)
    $reader = "$($Ev.data.reader)"
    $upTo = [long]$Ev.data.upTo
    if ($upTo -ge [long]$Ev.sequence) { return ("it says '" + $reader + "' has read up to record " + $upTo + ", which is not before this record (" + $Ev.sequence + "): nothing is read before it is written") }
    $had = Get-HordeDecisionReadMark -State $State -Reader $reader
    if ($upTo -le $had) { return ("it marks nothing as read: '" + $reader + "' had already read up to record " + $had) }
    $State.readMarks[$reader] = $upTo
    $State.readEvents[[long]$Ev.sequence] = [pscustomobject]@{ reader = $reader; from = $had; upTo = $upTo }
    return ""
}

function Get-HordeDecisionReadMark {
    # How far -Reader has read what others said: a record's sequence number, or 0 for nothing yet.
    param($State, [string]$Reader)
    if ($State.readMarks.ContainsKey($Reader)) { return [long]$State.readMarks[$Reader] }
    return [long]0
}

function Get-HordeDecisionMessagesFor {
    # What others said that -Reader is to read: every message, under any question, by a speaker other
    # than -Reader, whose record is after -After and at or before -UpTo. In store order, oldest first,
    # each as { question; message }. With no -After it starts from the reader's own mark,
    # which is "what it has not read yet"; a repost of a marking names the two ends it recorded.
    param($State, [Parameter(Mandatory = $true)][string]$Reader, [long]$After = -1, [long]$UpTo = [long]::MaxValue)
    if ($After -lt 0) { $After = Get-HordeDecisionReadMark -State $State -Reader $Reader }
    $found = New-Object System.Collections.ArrayList
    foreach ($question in $State.questions.Values) {
        foreach ($message in $question.thread) {
            if ($message.speaker -ceq $Reader) { continue }
            if ([long]$message.sequence -le $After -or [long]$message.sequence -gt $UpTo) { continue }
            [void]$found.Add([pscustomobject]@{ question = $question; message = $message })
        }
    }
    return @($found | Sort-Object { [long]$_.message.sequence })
}

function Test-HordeDecisionEvent {
    # Findings for a parsed record's SHAPE: the envelope, its kind, and its kind's data, each against
    # its schema. Empty means the record can be applied. One function, used for a stored record and for
    # a record about to be written, so nothing is ever written that the reader would call unreadable.
    param($Ev, $Definitions)
    $found = @(Test-HordeDecisionEnvelope -Ev $Ev -Definitions $Definitions)
    if ($found.Count -gt 0) { return $found }
    $entry = $script:HordeDecisionEventKinds["$($Ev.kind)"]
    if ($null -eq $entry) { return @("its kind '" + $Ev.kind + "' is not one this version of Horde knows; a newer version may have written it") }
    $dataSchema = Get-HordeDecisionMember -Object $Definitions.eventSchema.definitions -Name $entry.data
    $found = @(Test-HordeSchema -Value $Ev.data -Schema $dataSchema -Path '$.data' -Root $Definitions.eventSchema)
    if ($found.Count -eq 0 -and $entry.words -ne "") {
        $found = @(Test-HordeSchema -Value (Get-HordeDecisionMember -Object $Ev.data -Name $entry.words) -Schema $Definitions.questionSchema -Path ('$.data.' + $entry.words))
    }
    if ($found.Count -gt 0) { return @("its data is not what a " + $Ev.kind + " record holds: " + (@($found | Select-Object -First 3) -join "; ")) }
    if ($entry.about -ceq "question" -and -not (Test-HordeDecisionCount -Value $Ev.data.number -Most $script:HordeDecisionMaxNumber)) { return @("its question number is beyond " + $script:HordeDecisionMaxNumber + ", the largest a question can have") }
    # Every other count the kind carries, held to the same two limits and for the same reason: a
    # number the schema calls an integer and a cast would throw on.
    foreach ($member in @($entry.counts.Keys)) {
        $most = $script:HordeDecisionMaxNumber
        if ($entry.counts[$member] -ceq "sequence") { $most = (Get-HordeDecisionMaxSequence) }
        # A count the record does not carry is not asked: whether it must is its schema's to say.
        if (-not (Test-HordeDecisionMember -Object $Ev.data -Name $member)) { continue }
        if (-not (Test-HordeDecisionCount -Value (Get-HordeDecisionMember -Object $Ev.data -Name $member) -Most $most)) { return @("its '" + $member + "' is beyond " + $most + ", the largest it can be") }
    }
    return @()
}

function Add-HordeDecisionRecordToState {
    # Apply one record of the store (decisions/Store.ps1: { sequence; span; file; kind; data; reason })
    # to the list. Returns "" when it applied, or why it did not; either way the list says so itself, in
    # .unreadable or .ignored, so a caller that only shows the list still shows the problem.
    # span is how many numbers of the order the entry covers: 1, or for a gap of missing records, all
    # of them at once. An entry with no span covers one.
    param($State, $Record, $Definitions)
    $span = [long]1
    if (Test-HordeDecisionMember -Object $Record -Name "span") { $span = [long]$Record.span }
    $State.lastSequence = [long]$Record.sequence + $span - 1
    $why = ""
    if ($Record.kind -cne "ok") { $why = "$($Record.reason)" }
    else {
        # The envelope first, and the record's place: only a record that passes both is believed about
        # anything, its kind's name included.
        $cover = @(Test-HordeDecisionEnvelope -Ev $Record.data -Definitions $Definitions)
        if ($cover.Count -gt 0) { $why = $cover[0] }
        elseif ([long]$Record.data.sequence -ne [long]$Record.sequence) { $why = "it says it is record " + $Record.data.sequence + ", which is not its place in the store" }
        elseif ($null -eq $script:HordeDecisionEventKinds["$($Record.data.kind)"]) {
            # NOT UNDERSTOOD BY THIS VERSION (the compatibility contract in the header): set aside, counted
            # under its kind, its id remembered - and never a possible question, so nothing is added to
            # the numbers left unused.
            $later = "$($Record.data.kind)"
            if ($State.notUnderstood.Contains($later)) { $seen = $State.notUnderstood[$later]; $seen.count = [int]$seen.count + 1; $seen.last = [long]$Record.sequence }
            else { $State.notUnderstood[$later] = [pscustomobject]@{ kind = $later; count = 1; first = [long]$Record.sequence; last = [long]$Record.sequence } }
            if (-not $State.ids.ContainsKey("$($Record.data.id)")) {
                $State.ids["$($Record.data.id)"] = [pscustomobject]@{ sequence = [long]$Record.sequence; kind = $later; requestHash = "$($Record.data.requestHash)"; number = 0; applied = $false }
            }
            # ITS NUMBER STILL RAISES THE FLOOR (the contract's last point): a number field shaped like
            # a question number is taken as a number that may have been given, and the next question is
            # above it. It only ever raises: a number at or below the next one changes nothing.
            $carried = Get-HordeDecisionMember -Object $Record.data.data -Name "number"
            if ((Test-HordeDecisionCount -Value $carried -Most $script:HordeDecisionMaxNumber) -and [double]$carried -gt ([double]$State.lastNumber + [double]$State.pending)) {
                $State.lastNumber = [int]$carried; $State.pending = 0
            }
            return ""
        }
        else {
            $shape = @(Test-HordeDecisionEvent -Ev $Record.data -Definitions $Definitions)
            if ($shape.Count -gt 0) { $why = $shape[0] }
        }
    }
    if ($why -ne "") {
        # A long reason is cut, and says so: a damaged record can produce findings of any length.
        if ($why.Length -gt 400) { $why = $why.Substring(0, 400) + " (reason cut at 400 characters)" }
        [void]$State.unreadable.Add([pscustomobject]@{ sequence = [long]$Record.sequence; file = "$($Record.file)"; reason = $why })
        # Any of the records an unreadable entry covers may have been a question: one number each.
        $State.pending = [int]$span + [int]$State.pending
        return $why
    }
    $Ev = $Record.data
    $entry = $script:HordeDecisionEventKinds["$($Ev.kind)"]
    $applied = & $entry.apply $State $Ev
    if ("$applied" -ne "") { [void]$State.ignored.Add([pscustomobject]@{ sequence = [long]$Record.sequence; file = "$($Record.file)"; reason = "$applied" }) }
    # The first record of an id is the one a repost is answered from. number is the question it was
    # about, or 0 for a record about the whole list.
    if (-not $State.ids.ContainsKey("$($Ev.id)")) {
        $about = 0
        if ($entry.about -ceq "question") { $about = [int]$Ev.data.number }
        $State.ids["$($Ev.id)"] = [pscustomobject]@{ sequence = [long]$Record.sequence; kind = "$($Ev.kind)"; requestHash = "$($Ev.requestHash)"; number = $about; applied = ("$applied" -eq "") }
    }
    return "$applied"
}

function ConvertTo-HordeDecisionState {
    # THE FOLD: the store's records, in order, become the current list. Nothing is cached and nothing
    # else is consulted, so the records are the single source of truth.
    param($Records, $Definitions)
    $state = New-HordeDecisionState
    foreach ($record in @($Records)) { $null = Add-HordeDecisionRecordToState -State $state -Record $record -Definitions $Definitions }
    return $state
}

function ConvertTo-HordeDecisionMessageView {
    # One message as plain data, schema/decision-result.v1's message. ONE THING IS DERIVED HERE, at the
    # moment of showing: unreadBy, from the readers' marks - the roles that have an inbox, other than
    # the speaker, that have not read up to this record. The two flags were worked out in the fold, at
    # the record's place in the order, and are only copied. speakerShown and routeShown are this
    # file's words for the two labels, handed out so that every way of showing says "recorded by the
    # warchief from chat" in the same words.
    param($Message, $State)
    $unreadBy = New-Object 'System.Collections.Generic.List[string]'
    foreach ($reader in @(Get-HordeDecisionReaders)) {
        if ($reader -cne $Message.speaker -and [long]$Message.sequence -gt (Get-HordeDecisionReadMark -State $State -Reader $reader)) { $unreadBy.Add($reader) }
    }
    return [pscustomobject]@{
        sequence = [long]$Message.sequence; at = "$($Message.at)"
        speaker = "$($Message.speaker)"; speakerShown = (Get-HordeDecisionSpeakerShown -Speaker "$($Message.speaker)")
        route = "$($Message.route)"; routeShown = (Get-HordeDecisionRouteShown -Route "$($Message.route)")
        recordedBy = "$($Message.recordedBy)"
        text = [string]$Message.text
        holdsDirectionOrInvisibleCharacters = [bool]([regex]::IsMatch([string]$Message.text, $script:HordeDecisionDirectionOrInvisible))
        wordingStated = [bool]$Message.wordingStated
        wordingVersion = [int]$Message.wordingVersion
        saidToEarlierWording = [bool]$Message.saidToEarlierWording
        arrivedAfterClosing = [bool]$Message.arrivedAfterClosing
        unreadBy = $unreadBy.ToArray()
        asks = [bool]$Message.asks
        act = "$($Message.act)"
        replaces = [bool]$Message.replaces
        evidence = "$($Message.evidence)"
        signedBy = "$($Message.signedBy)"
    }
}

function ConvertTo-HordeDecisionThreadView {
    # A question's conversation as plain data: how many messages, whose turn it is, and how many each
    # reader has not read - and, with -Messages, the messages themselves in store order. A list gives
    # the counts; one question shown gives the whole thread.
    param($Question, $State, [switch]$Messages)
    $views = @($Question.thread | ForEach-Object { ConvertTo-HordeDecisionMessageView -Message $_ -State $State })
    $unread = New-Object System.Collections.ArrayList
    foreach ($reader in @(Get-HordeDecisionReaders)) {
        [void]$unread.Add([pscustomobject]@{ reader = $reader; readerShown = (Get-HordeDecisionSpeakerShown -Speaker $reader); count = @($views | Where-Object { $_.unreadBy -ccontains $reader }).Count })
    }
    $turn = "$($Question.turn)"
    $turnShown = $turn
    if ($turn -cne $script:HordeDecisionNoTurn) { $turnShown = Get-HordeDecisionSpeakerShown -Speaker $turn }
    $thread = [ordered]@{ count = $views.Count; turn = $turn; turnShown = $turnShown; unread = @($unread) }
    if ($Messages) { $thread["messages"] = $views }
    return [pscustomobject]$thread
}

function ConvertTo-HordeDecisionView {
    # One question of the list as plain data, schema/decision-result.v1's view: a copy, so nothing a
    # caller does to it reaches the list. -State is the list the question is in, which is where what
    # is unread comes from; -Messages puts the whole conversation in, and without it only its counts.
    param($Question, $State, [switch]$Messages)
    $view = [ordered]@{ number = [int]$Question.number; state = "$($Question.state)"; wordingVersion = [int]$Question.wordingVersion }
    foreach ($name in $script:HordeDecisionFields.Keys) {
        $type = $script:HordeDecisionFields[$name].type
        if ($type -eq "list") { $view[$name] = [string[]]@($Question[$name]) }
        elseif ($type -eq "flag") { $view[$name] = [bool]$Question[$name] }
        else { $view[$name] = "$($Question[$name])" }
    }
    foreach ($name in @("outcome", "reopenReason", "addedAt", "updatedAt", "closedAt")) { $view[$name] = "$($Question[$name])" }
    $view["history"] = @($Question.history | ForEach-Object { [pscustomobject]@{ sequence = $_.sequence; kind = $_.kind; at = $_.at; actor = $_.actor; note = $_.note } })
    $view["thread"] = ConvertTo-HordeDecisionThreadView -Question $Question -State $State -Messages:$Messages
    return [pscustomobject]$view
}
