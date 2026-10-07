# DO THE DECISIONS RULES GIVE EVERY QUESTION ONE NUMBER FOR EVER, AND REFUSE WHAT MUST NOT BE WRITTEN?
#
# decisions/Rules.ps1 alone, with no store and no file but the module's own definitions: records are
# built here as values and folded. This suite attacks:
#   - THE NUMBER. The Nth question-added record is question N; closing, reopening and changing never
#     move a number or free one; and a record that becomes unreadable AFTER later questions were added
#     does not renumber them.
#   - THE FOLD. A torn record, a record of another schema, a kind this version does not know and a
#     record that contradicts the order are each reported and none stops the list.
#   - A QUESTION EXPLAINS ITSELF. A title that is only a number or a reference, or too short, is
#     refused; so is a question with neither background nor "what yes means".
#   - NO SECRETS, AND NO ECHO. Every kind of credential is refused in any field, by name of the field,
#     and the finding never repeats it. Controls show ordinary content is let through.
#   - THE CONVERSATION UNDER A QUESTION. Words said are kept in store order, whatever the question's
#     state and whatever wording they were said to; they change nothing of the question; whose turn it
#     is and what is unread are worked out from the order and never stored; who may speak, by what
#     route, and who may record whose words are closed lists.
# The secrets below are assembled from pieces at run time, so that no credential-shaped text sits in
# this file for a scanner to find.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Rules.ps1")
. (Join-Path $root "decisions\Definitions.ps1")

$defs = Get-HordeDecisionDefinitions
$zeros = "0" * 64

function New-Question {
    # A question that passes every rule, with -Over replacing or adding fields.
    param([hashtable]$Over = @{})
    $q = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."
            group = "voice"; askedBy = "orc-b" }
    foreach ($k in @($Over.Keys)) { $q[$k] = $Over[$k] }
    return $q
}
function Get-Findings {
    # The findings for a question given as a table; a throw becomes a finding, so a mutant that makes
    # the rules throw fails a check instead of crashing the suite.
    param([hashtable]$Question)
    # Returned with the unary comma: no findings must arrive as an empty list, not as nothing.
    $found = @()
    try { $found = @(Test-HordeDecisionQuestion -Question (ConvertTo-HordeDecisionFields -Source $Question) -Kinds $defs.kinds) } catch { $found = @("THREW: " + $_.Exception.Message) }
    return ,$found
}
function Test-Says { param($Findings, [string]$Text) return (@($Findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function New-Record {
    # One stored record as the store hands it over: the envelope written as JSON and read back.
    param([long]$Seq, [string]$Kind, $Data, [string]$Id = "", [int]$Version = 1, [long]$SaysSeq = -1)
    if ($Id -eq "") { $Id = $Seq.ToString("x32") }
    if ($SaysSeq -lt 0) { $SaysSeq = $Seq }
    $envelope = [ordered]@{ schemaVersion = $Version; sequence = $SaysSeq; id = $Id; kind = $Kind; at = ("2026-10-06T12:00:" + ($Seq % 60).ToString("00") + ".0000000Z"); actor = "warchief"; requestHash = $zeros; data = $Data }
    return [pscustomobject]@{ sequence = $Seq; file = ($Seq.ToString("D10") + ".json"); kind = "ok"; data = ((ConvertTo-Json -InputObject $envelope -Compress -Depth 12) | ConvertFrom-Json); reason = "" }
}
function New-Added { param([long]$Seq, [int]$Number, [string]$Title = "") if ($Title -eq "") { $Title = "Is question number $Number asked in plain words here?" }; return (New-Record -Seq $Seq -Kind "question-added" -Data ([ordered]@{ number = $Number; question = (ConvertTo-HordeDecisionFields -Source (New-Question @{ title = $Title })) })) }
function New-Torn { param([long]$Seq) return [pscustomobject]@{ sequence = $Seq; file = ($Seq.ToString("D10") + ".json"); kind = "torn"; data = $null; reason = "it is not complete JSON: its writer stopped while writing it, or it was damaged" } }
function Get-Fold {
    param($Records)
    try { return (ConvertTo-HordeDecisionState -Records $Records -Definitions $defs) } catch { Write-Host ("         the fold threw: " + $_.Exception.Message) -ForegroundColor Red; return (New-HordeDecisionState) }
}
function Get-Numbers { param($State) return (@($State.questions.Keys) -join ",") }

Write-Host ""
Write-Host "--- one definition of each thing ---" -ForegroundColor Cyan
$schemaFields = @($defs.questionSchema.properties.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
$tableFields = @(Get-HordeDecisionFieldNames | Sort-Object)
Check (($schemaFields -join ",") -ceq ($tableFields -join ",")) "the rules' field table and schema/decision-question.v1 name the same fields"
Check ($tableFields.Count -eq 14) ("CONTROL: there are fourteen fields (" + $tableFields.Count + ")")
$viewFields = @($defs.resultSchema.definitions.view.properties.PSObject.Properties | ForEach-Object { $_.Name })
Check (@($tableFields | Where-Object { $viewFields -cnotcontains $_ }).Count -eq 0) "and a question as shown (decision-result.v1) carries every one of them"
$kindNames = @(Get-HordeDecisionEventKinds)
$defNames = @($defs.eventSchema.definitions.PSObject.Properties | ForEach-Object { $_.Name })
Check (($kindNames -join ",") -ceq "question-added,question-updated,question-closed,question-reopened,message-said,messages-read") "the event kinds are the four that change a question, and the two of the conversation under it"
Check (((Get-HordeDecisionSpeakers) -join ",") -ceq "founder,warchief" -and ((Get-HordeDecisionRoutes) -join ",") -ceq "window,chat-recorded,command" -and ((Get-HordeDecisionReaders) -join ",") -ceq "warchief") "who speaks, by what routes, and who has an inbox are the rules' closed lists"
Check (@($kindNames | Where-Object { @("question", "list") -cnotcontains (Get-HordeDecisionKindAbout -Kind $_) }).Count -eq 0 -and (Get-HordeDecisionKindAbout -Kind "messages-read") -ceq "list" -and (Get-HordeDecisionKindAbout -Kind "message-said") -ceq "question" -and (Get-HordeDecisionKindAbout -Kind "no-such-kind") -ceq "") "every kind says what it is about: one question, or the whole list"
Check (((Get-HordeDecisionKindActors -Kind "question-closed").roles -join ",") -ceq "warchief" -and ((Get-HordeDecisionKindActors -Kind "message-said").roles -join ",") -ceq "founder,warchief" -and ((Get-HordeDecisionKindActors -Kind "messages-read").roles -join ",") -ceq "founder,warchief") "a question's own records are written by its keepers, and what is said under it by its speakers"
Check ((@($kindNames | Sort-Object) -join ",") -ceq (@($defNames | Sort-Object) -join ",")) "every event kind has its data definition in schema/decision-event.v1, and every definition has a kind"
$unbacked = @($kindNames | Where-Object { $null -eq (Get-Command -Name $script:HordeDecisionEventKinds[$_].apply -CommandType Function -ErrorAction SilentlyContinue) })
Check ($unbacked.Count -eq 0) "and every kind's function exists"
Check ((@($defs.kinds.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "yes-no,choice,value,parts,do-then-say") "the question kinds are the five of the design, from the one table"
Check (@($defs.kinds.PSObject.Properties | Where-Object { "$($_.Value.label)".Trim() -eq "" -or "$($_.Value.means)".Trim() -eq "" }).Count -eq 0) "each with a label and one definition in a sentence"
Check ((Get-HordeDecisionStates) -join "," -ceq "open,closed") "a question is open or closed in this slice"
# WHO MAY WRITE is the rules' closed list, beside the states and the event kinds - not an enum in the
# event schema, where a second actor would have been a change to "v1" that every older checkout then
# read as an unreadable record.
$actorNames = "THREW"
try { $actorNames = (@(Get-HordeDecisionActors) -join ",") } catch { }
Check ($actorNames -ceq "warchief") ("the actors of this slice are the rules' own list: the warchief alone (" + $actorNames + ")")
Check ($null -eq $defs.eventSchema.properties.actor.PSObject.Properties["enum"] -and "$($defs.eventSchema.properties.actor.pattern)" -ne "") "and the event schema holds no list of them: only that an actor is one lowercase label"

Write-Host ""
Write-Host "--- a title must explain itself ---" -ForegroundColor Cyan
foreach ($bad in @("7", "#7?", "1469", "PR 1469?", "pr 1469", "pull request 1469", "Pull-request #1469?", "Issue 94?", "issues 94, 95", "PRs 12 and 13?")) {
    $f = Get-Findings (New-Question @{ title = $bad })
    Check ($f.Count -eq 1 -and ((Test-Says $f "only a pull-request or issue reference") -or (Test-Says $f "no letters") -or (Test-Says $f "too short"))) ("refused: '" + $bad + "'")
}
Check (Test-Says (Get-Findings (New-Question @{ title = "PR 1469?" })) "only a pull-request or issue reference") "'PR 1469?' is refused as only a reference, and told where a reference belongs"
# THE SAME REFERENCES IN THE TWO SPELLINGS THE RULE FIRST MISSED (measured 2026-10-06, each was added
# as a question): the word joined to its number, where there is no word boundary between them, and a
# link, whose host and path counted as six words.
foreach ($bad in @("PR1469 PR1470 PR1471", "issue7, issue8 and issue9?", "https://github.com/acme/app/pull/12", "See https://github.com/acme/app/pull/12 and https://github.com/acme/app/issues/7")) {
    $f = Get-Findings (New-Question @{ title = $bad })
    Check ($f.Count -eq 1 -and ((Test-Says $f "only a pull-request or issue reference") -or (Test-Says $f "too short"))) ("refused: '" + $bad + "'" + $(if ($f.Count -ne 1) { " (" + $f.Count + " finding(s))" } else { "" }))
}
Check (Test-Says (Get-Findings (New-Question @{ title = "https://github.com/acme/app/pull/12" })) "only a pull-request or issue reference") "a title that is only a link is refused as only a reference"
foreach ($good in @("Should the closing sound follow https://example.org/sound-notes or stay silent?", "Is the press release ready to send?", "Does the bugfix for the reader need another device test?")) {
    $f = Get-Findings (New-Question @{ title = $good })
    Check ($f.Count -eq 0) ("CONTROL: accepted: '" + $good + "'" + $(if ($f.Count) { " (" + ($f -join "; ") + ")" } else { "" }))
}
Check (Test-Says (Get-Findings (New-Question @{ title = "1469" })) "no letters") "a title that is only a number is refused as having no letters"
Check (Test-Says (Get-Findings (New-Question @{ title = "???" })) "no letters") "so is a title of punctuation"
Check (Test-Says (Get-Findings (New-Question @{ title = "Merge PR 1469?" })) "too short") "'Merge PR 1469?' is refused: one word beside the reference does not explain it"
Check (Test-Says (Get-Findings (New-Question @{ title = "Close pull request 1469?" })) "too short") "the words 'pull request' do not count as explaining: 'Close pull request 1469?' is refused"
Check (Test-Says (Get-Findings (New-Question @{ title = "Ship it?" })) "too short") "'Ship it?' is refused as too short"
Check (Test-Says (Get-Findings (New-Question @{ title = "   " })) "'title' is missing or blank") "a blank title is missing"
$hebrewTitle = "" + [char]0x05D4 + [char]0x05D0 + [char]0x05DD + " " + [char]0x05DC + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05D7 + " " + [char]0x05D0 + [char]0x05EA + " " + [char]0x05D4 + [char]0x05E7 + [char]0x05D5 + [char]0x05D1 + [char]0x05E5 + "?"
foreach ($good in @("Should the closing sound play when the assistant closes?", "Fix the bug where one registration code can register two devices?", "Merge the zoom-limit fix (PR 1583) after it is tested on a device?", "Test near and far distances too?", "Write to them now?", $hebrewTitle)) {
    $f = Get-Findings (New-Question @{ title = $good })
    Check ($f.Count -eq 0) ("CONTROL: accepted: a title in plain words" + $(if ($f.Count) { " (" + ($f -join "; ") + ")" } else { "" }))
}

# A SCRIPT THAT WRITES NO SPACES BETWEEN WORDS is judged by its letters. Measured 2026-10-06: a Chinese
# sentence of eleven characters was refused as "1 word(s)", because a word was a run of letters.
$chinese = "" + [char]0x6211 + [char]0x4EEC + [char]0x5E94 + [char]0x8BE5 + [char]0x5408 + [char]0x5E76 + [char]0x8FD9 + [char]0x4E2A + [char]0x4FEE + [char]0x590D + [char]0x5417 + "?"
$japanese = "" + [char]0x3053 + [char]0x306E + [char]0x4FEE + [char]0x6B63 + [char]0x3092 + [char]0x30DE + [char]0x30FC + [char]0x30B8 + [char]0x3057 + [char]0x307E + [char]0x3059 + [char]0x304B + "?"
$thai = "" + [char]0x0E04 + [char]0x0E27 + [char]0x0E23 + [char]0x0E23 + [char]0x0E27 + [char]0x0E21 + [char]0x0E44 + [char]0x0E2B + [char]0x0E21
foreach ($good in @($chinese, $japanese, $thai)) {
    $f = Get-Findings (New-Question @{ title = $good })
    Check ($f.Count -eq 0) ("CONTROL: accepted: a title of " + $good.Length + " characters in a script that writes no spaces" + $(if ($f.Count) { " (" + ($f -join "; ") + ")" } else { "" }))
}
Check (Test-Says (Get-Findings (New-Question @{ title = ("" + [char]0x5408 + [char]0x5E76 + "?") })) "too short") "two such letters are still too short to explain anything"
Check (Test-Says (Get-Findings (New-Question @{ title = ("PR 1469 " + [char]0x5408 + [char]0x5E76 + "?") })) "too short") "and a reference beside them does not help"
Check (Test-Says (Get-Findings (New-Question @{ title = "Ship it?" })) "it has 2 word(s)") "CONTROL: a title in a script that does write spaces is still counted in words"

Write-Host ""
Write-Host "--- what a question must hold ---" -ForegroundColor Cyan
Check ((Get-Findings (New-Question)).Count -eq 0) "CONTROL: the base question passes every rule"
Check (Test-Says (Get-Findings (New-Question @{ whatItIs = ""; yesMeans = "" })) "must explain itself") "a question with neither whatItIs nor yesMeans is refused"
Check ((Get-Findings (New-Question @{ whatItIs = ""; yesMeans = "A short tone plays." })).Count -eq 0) "CONTROL: yesMeans alone is enough"
foreach ($need in @("kind", "group", "askedBy")) {
    Check (Test-Says (Get-Findings (New-Question @{ $need = "" })) ("'" + $need + "' is missing or blank")) ("a question with no " + $need + " is refused")
}
Check ((Get-Findings (New-Question @{ recommendation = ""; waiting = @(); groupNote = "" })).Count -eq 0) "CONTROL: no recommendation, nobody waiting and no group note are all allowed"
Check (Test-Says (Get-Findings (New-Question @{ kind = "maybe" })) "is not a kind of question") "a kind the table does not hold is refused, and the kinds are listed"
Check (Test-Says (Get-Findings (New-Question @{ kind = "choice" })) "needs at least two options") "a choice with no options is refused"
Check (Test-Says (Get-Findings (New-Question @{ kind = "choice"; options = @("only one") })) "needs at least two options") "a choice with one option is refused"
Check ((Get-Findings (New-Question @{ kind = "choice"; options = @("Hebrew", "Spanish") })).Count -eq 0) "CONTROL: a choice with two options passes"
Check (Test-Says (Get-Findings (New-Question @{ kind = "choice"; options = @("same", "same") })) "names one item twice") "a choice naming one option twice is refused"
Check (Test-Says (Get-Findings (New-Question @{ kind = "parts"; parts = @("only one") })) "needs at least two parts") "a question in parts with one part is refused"
Check ((Get-Findings (New-Question @{ kind = "parts"; parts = @("the wait starts when she listens", "any reply cancels the close") })).Count -eq 0) "CONTROL: two parts pass"
Check (Test-Says (Get-Findings (New-Question @{ options = @("a", "b") })) "'options' is given, but a question of kind yes-no has none") "options on a yes-no question are refused, not stored and never shown"
Check (Test-Says (Get-Findings (New-Question @{ kind = "choice"; options = @("a", "b"); parts = @("x", "y") })) "'parts' is given") "parts on a choice are refused"
Check (Test-Says (Get-Findings (New-Question @{ waiting = @("orc-b", " ") })) "'waiting' (item 2) is blank") "a blank item in a list is refused, by its place"
Check (Test-Says (Get-Findings (New-Question @{ title = "Should the closing sound`nplay when the assistant closes?" })) "'title' must be one line") "a title with a line break is refused"
Check ((Get-Findings (New-Question @{ whatItIs = "Line one.`r`nLine two.`nLine three." })).Count -eq 0) "CONTROL: the background may have as many lines as it needs"
$long = "word " * 20000
Check ((Get-Findings (New-Question @{ whatItIs = $long })).Count -eq 0) "CONTROL: a 100,000-character background passes"
$f = Get-Findings (New-Question @{ whatItIs = ("word " * 100000) + "!" })
Check ((Test-Says $f "'whatItIs' is 500001 characters long") -and (Test-Says $f "never cut")) "a 500,001-character background is refused whole, with its length, and says it is not cut"
Check (Test-Says (Get-Findings (New-Question @{ group = ("g" * 1001) })) "'group' is 1001 characters long") "a one-line field over 1,000 characters is refused"
Check (Test-Says (Get-Findings (New-Question @{ waiting = @(1..101 | ForEach-Object { "orc-" + $_ }) })) "'waiting' has 101 items") "a list of more than 100 items is refused"
$note = @(Test-HordeDecisionNote -Text "  " -Name "outcome")
Check (Test-Says $note "'outcome' is blank") "a closing outcome must say something"
Check (Test-Says @(Test-HordeDecisionNote -Text "one`ntwo" -Name "reason" -OneLine) "must be one line") "a reopening reason is one line"
Check (@(Test-HordeDecisionNote -Text "Built and shipped.`nSecond line." -Name "outcome").Count -eq 0) "CONTROL: an outcome may have several lines"

Write-Host ""
Write-Host "--- characters that are not text: refused by field and code point, never cleaned ---" -ForegroundColor Cyan
# Measured 2026-10-06, before this rule: a title holding ESC [2J ESC [31m and a group holding BEL were
# added, and the plain-text list printed the raw ESC and BEL to the terminal, which obeys them. A line
# separator (U+2028) and a NUL were stored in a "one line" title too. Every character here is written
# by its code, so this file stays ASCII.
$base = "Should the closing sound play when it closes"
$oneLineBad = [ordered]@{ "ESC" = 0x1B; "BEL" = 0x07; "NUL" = 0x00; "a tab" = 0x09; "DEL" = 0x7F; "NEL, a C1 control" = 0x85; "a line separator" = 0x2028; "a paragraph separator" = 0x2029
    "a zero-width space" = 0x200B; "a right-to-left override" = 0x202E; "a left-to-right isolate" = 0x2066; "a byte-order mark" = 0xFEFF }
foreach ($what in $oneLineBad.Keys) {
    $code = [int]$oneLineBad[$what]
    $f = Get-Findings (New-Question @{ title = ($base + [char]$code + " or stay silent?") })
    Check ($f.Count -eq 1 -and (Test-Says $f ("'title' holds the character U+" + $code.ToString("X4")))) ("a title holding " + $what + " is refused, by field and code point (U+" + $code.ToString("X4") + ")" + $(if ($f.Count -ne 1) { " (" + $f.Count + " finding(s))" } else { "" }))
}
$f = Get-Findings (New-Question @{ kind = "choice"; options = @("a tone", ("a spoken" + [char]0x1B + "[31m line")) })
Check ($f.Count -eq 1 -and (Test-Says $f "'options' (item 2) holds the character U+001B")) "in a list the finding names the item"
$f = Get-Findings (New-Question @{ title = ($base + [char]0x1B + "?") })
Check ((Test-Says $f "refused, not removed") -and -not (Test-Says $f ("" + [char]0x1B))) "the finding says the text is refused, not cleaned, and does not carry the character itself"
$f = Get-Findings (New-Question @{ title = ("Should the closing sound`nplay when the assistant closes?") })
Check ($f.Count -eq 1 -and (Test-Says $f "must be one line")) "CONTROL: a line break in a title is still the one-line finding, said once"
# A text of several lines takes a line break and a tab, and nothing else that is not text.
Check ((Get-Findings (New-Question @{ whatItIs = ("Line one.`r`nLine two.`n`tIndented with a tab.") })).Count -eq 0) "CONTROL: a background may hold line breaks and tabs"
foreach ($what in @("ESC", "NUL", "a line separator", "a right-to-left override", "a zero-width space")) {
    $code = [int]$oneLineBad[$what]
    $f = Get-Findings (New-Question @{ whatItIs = ("Line one.`nLine " + [char]$code + "two.") })
    Check ($f.Count -eq 1 -and (Test-Says $f ("'whatItIs' holds the character U+" + $code.ToString("X4")))) ("a background holding " + $what + " is refused, by field and code point")
}
Check (Test-Says @(Test-HordeDecisionNote -Text ("Built." + [char]0x1B + "[2J") -Name "outcome") "'outcome' holds the character U+001B") "a closing outcome is held to the same rule"
Check (@(Test-HordeDecisionNote -Text "Built and shipped.`r`n`tSee the log." -Name "outcome").Count -eq 0) "CONTROL: an outcome may hold line breaks and tabs"
Check (Test-Says @(Test-HordeDecisionNote -Text ("it came" + [char]0x09 + "back") -Name "reason" -OneLine) "'reason' holds the character U+0009") "a reopening reason is one line: a tab in it is refused"
# FOUR FORMAT CHARACTERS ARE TEXT: the two direction marks and the two joiners. Right-to-left text is
# written with them, and the design requires it stored exactly. What can reorder or hide other text
# (an override, an isolate, a zero-width space) is refused above.
$hebrewWords = "" + [char]0x05D4 + [char]0x05D0 + [char]0x05DD + " " + [char]0x05DC + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05D7 + " " + [char]0x05D0 + [char]0x05EA + " " + [char]0x05D4 + [char]0x05E7 + [char]0x05D5 + [char]0x05D1 + [char]0x05E5
Check ((Get-Findings (New-Question @{ title = ($hebrewWords + "?") })).Count -eq 0) "CONTROL: a title in Hebrew passes"
foreach ($mark in @(0x200F, 0x200E, 0x200D, 0x200C)) {
    $f = Get-Findings (New-Question @{ title = ($hebrewWords + [char]$mark + "?"); whatItIs = ("Line one.`n" + $hebrewWords + [char]$mark + " line two.") })
    Check ($f.Count -eq 0) ("CONTROL: U+" + ([int]$mark).ToString("X4") + " in a title and in a background is text, and passes" + $(if ($f.Count) { " (" + ($f -join "; ") + ")" } else { "" }))
}

Write-Host ""
Write-Host "--- no secrets, in any field, and never repeated ---" -ForegroundColor Cyan
$secrets = [ordered]@{
    "a private key" = ("-----BEGIN RSA PRIV" + "ATE KEY-----")
    "an access token" = ("gh" + "p_" + ("Ab1" * 12))
    "a signed web token" = ("ey" + "JhbGciOiJIUzI1NiJ9" + "." + "ey" + "JzdWIiOiIxMjM0In0" + "." + "c2ln")
    "a bearer token" = ("Bea" + "rer " + ("a1b2c3d4e5" * 3))
    "a password or key written as name=value" = ("pass" + "word=" + "hunter2")
    "a password written after a colon" = ("Pass" + "word: " + "hunter2x")
    "a long random-looking string" = ("Zx9Qm2Lp7Rt4Vb8Nc1Hd" + "6Jf3Kg5Ws0YaUe4Ti7Ro")
}
foreach ($name in $secrets.Keys) {
    $secret = $secrets[$name]
    $found = @(Find-HordeDecisionSecrets -Value ([pscustomobject]@{ question = [pscustomobject]@{ title = "A plain title"; whatItIs = ("The login is " + $secret + " for now.") } }))
    Check ($found.Count -eq 1 -and (Test-Says $found "'whatItIs' holds what looks like") -and (Test-Says $found $name)) ("refused in whatItIs, named as " + $name)
    Check (-not (Test-Says $found $secret) -and -not (Test-Says $found "hunter2") -and -not (Test-Says $found "Zx9Qm2")) "and the finding does not repeat it"
}
$more = @("gh" + "o_" + ("Cd2" * 12); "github" + "_pat_" + ("Ef3" * 10); "gl" + "pat-" + ("Gh4" * 8); "xo" + "xb-" + ("123456789012" * 2); "s" + "k-" + ("Ij5" * 10); "AK" + "IA" + "ABCDEFGHIJKLMNOP"; "AS" + "IA" + "QRSTUVWXYZ234567"; "AI" + "za" + ("Kl6" * 12); "api_" + "key = " + "abc"; "TOK" + "EN=" + "x"; "-----BEGIN PRIV" + "ATE KEY-----"; "-----BEGIN EC PRIV" + "ATE KEY-----")
$missed = @($more | Where-Object { (Find-HordeDecisionSecretKind -Text ("see " + $_ + " here")) -eq "" })
Check ($missed.Count -eq 0) ("twelve more credential shapes are each refused: other token prefixes, cloud key ids, name = value with spaces, other key headers (" + $missed.Count + " missed)")
# THE SHAPES THE FIRST CHECK LET THROUGH. Measured 2026-10-06: each of these was ADDED to a store.
# Assembled from pieces, like the rest, so no credential-shaped text sits in this file.
$let = [ordered]@{
    "a cloud secret key with slashes in it" = @(("wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY"), "a long random-looking string")
    "a storage key with slashes and padding" = @(("kq3J9s/Zr8/Lm2Xv0Bn5Ty7Uw1Ae4Cd6Fg8Hj0Kl2M/aQ" + "=="), "a long random-looking string")
    "an address with a user and a password in it" = @(("https://deploy:Tr0ub4dor3x@" + "git.example.com/repo.git"), "a password inside an address")
    "a database address with a password in it" = @(("postgres://app:s3cretWord@" + "db.internal:5432/main"), "a password inside an address")
    "a chat webhook address" = @(("https://hooks.slack.com/services/T00000000/B00000000/" + "XXXXXXXXXXXXXXXXXXXXXXXX"), "a webhook address")
    "an Authorization header, Basic" = @(("Authorization: Basic " + "ZGVwbG95OlRyMHViNGRvcjM="), "an authorization value")
    "an Authorization header, Bearer, short" = @(("Authorization: Bearer " + "abc123def"), "an authorization value")
    "the word Basic and a value" = @(("send Basic " + "ZGVwbG95OlRyMHViNGRvcjM=" + " with it"), "an authorization value")
    "the word Bearer and a short value" = @(("use Bearer " + "aB3dE5fG7hJ9k" + " for now"), "an authorization value")
    "a password said in a sentence" = @(("the pass" + "word is hunter2"), "a password written in a sentence")
    "a password said in a sentence, quoted" = @(("the pass" + "word is 'correct horse battery staple'"), "a password written in a sentence")
    "a password that was" = @(("the old pass" + "phrase was Winter2026!"), "a password written in a sentence")
    "a password after a colon, quoted" = @(("pass" + 'word: "correct horse"'), "a password written after a colon")
    "a password after a colon, digits only" = @(("pw" + "d: 12345678"), "a password written after a colon")
    "pwd= in a sentence" = @(("run it with pw" + "d=hunter2 set"), "a password or key written as name=value")
}
foreach ($what in $let.Keys) {
    $text = $let[$what][0]
    $found = @(Find-HordeDecisionSecrets -Value ([pscustomobject]@{ question = [pscustomobject]@{ whatItIs = ("For now it is " + $text + " as agreed.") } }))
    Check ($found.Count -eq 1 -and (Test-Says $found $let[$what][1])) ("refused: " + $what + ", named as " + $let[$what][1] + $(if ($found.Count -eq 0) { " (let through)" } else { "" }))
    Check (@($found | Where-Object { "$_".Contains($text) -or "$_".Contains("hunter2") -or "$_".Contains("Tr0ub4") -or "$_".Contains("s3cret") -or "$_".Contains("correct horse") -or "$_".Contains("ZGVwbG95") -or "$_".Contains("wJalrX") }).Count -eq 0) "and the finding does not repeat it"
}
# WHAT MUST STILL PASS, each beside the shape it could be mistaken for.
$stillOrdinary = @(
    "api/v2/Customers/Invoices/Search/ByDateRange/Page"                # a mixed-case path with a digit: 4.32 bits a character, under the limit
    "src/Components/Dashboard/Widgets/Chart2/Renderer/Canvas"
    "See https://example.org/notes/closing-sound:draft for the proposal"   # a colon in a link, and no @
    "Write to support@example.org or see https://example.org/help"         # an @ that is not in the link
    "The basic understanding is that Version2Reader replaces it"           # the word basic before an ordinary word
    "The bearer of the news was Orc3 again"
    "Authorization: none is needed for this page"
    "A password is needed before this can be tested"
    "The password was changed on 2026-10-06 and is not written here"
    "The password is at least 12 characters, by the new rule"
    "password: ask whoever owns the test account"
    "07af8361c2d4e5f60718293a4b5c6d7e8f901234"
    "0273216a-4aa6-420b-8bd6-b5d61a13d73d"
)
$wronglyNow = @($stillOrdinary | Where-Object { (Find-HordeDecisionSecretKind -Text $_) -ne "" })
Check ($wronglyNow.Count -eq 0) ("CONTROL: thirteen ordinary texts beside those shapes are let through: paths, links, the words basic, bearer, authorization and password in a sentence, a commit id, a UUID (" + $wronglyNow.Count + " refused" + $(if ($wronglyNow.Count) { ": " + (@($wronglyNow | ForEach-Object { $_.Substring(0, [Math]::Min(40, $_.Length)) }) -join " | ") } else { "" }) + ")")
# WHAT THE CHECK DELIBERATELY LETS THROUGH (decisions/Rules.ps1 says so): pinned, so it is a decision.
$letOnPurpose = @(("pass" + "word: correct horse battery staple"), "9f8e7d6c5b4a3z2y1x0w9v8u7t6s5r4q", "Zx9Qm2Lp7Rt4Vb8Nc1Hd")
Check (@($letOnPurpose | Where-Object { (Find-HordeDecisionSecretKind -Text $_) -ne "" }).Count -eq 0) "the stated limits: a password of plain words with no quotes, a long string in one case, and a mixed string under 32 characters are not seen"
$deep = [pscustomobject]@{ id = "x"; question = [pscustomobject]@{ options = @("fine", ("use " + $secrets["an access token"])); files = @("a.txt") }; outcome = $secrets["a private key"] }
$found = @(Find-HordeDecisionSecrets -Value $deep)
Check ($found.Count -eq 2 -and (Test-Says $found "'options' (item 2)") -and (Test-Says $found "'outcome'")) "a secret is found wherever it sits: an item of a list, and a text beside the question"
# A NAME IS TEXT TOO: a secret pasted where a field's name goes is found, and neither its own finding
# nor the finding for the value under it repeats it.
$tokenName = $secrets["an access token"]
$found = @(Find-HordeDecisionSecrets -Value ([pscustomobject]@{ question = (('{"title":"A plain title","' + $tokenName + '":"x"}') | ConvertFrom-Json) }))
Check ($found.Count -eq 1 -and (Test-Says $found "a field name in 'question' holds what looks like an access token")) ("a secret written as a field's name is found, and said to be a name (" + $found.Count + " finding(s))")
Check (-not (Test-Says $found $tokenName)) "and the finding does not repeat it"
$found = @(Find-HordeDecisionSecrets -Value ([pscustomobject]@{ question = (('{"' + $tokenName + '":"-----BEGIN PRIV' + 'ATE KEY-----"}') | ConvertFrom-Json) }))
Check ($found.Count -eq 2 -and (Test-Says $found "a private key") -and -not (Test-Says $found $tokenName)) ("a secret under a secret name: both are found, and the value's finding does not say where by repeating the name (" + $found.Count + " finding(s))")
Check (@(Find-HordeDecisionSecrets -Value ([pscustomobject]@{ question = [pscustomobject]@{ title = "A plain title"; colour = "red" } })).Count -eq 0) "CONTROL: an ordinary name the schema will refuse is not a secret"
$ordinary = @(
    "07af8361c2d4e5f60718293a4b5c6d7e8f901234"                       # a commit id: hex, one case
    "0273216a-4aa6-420b-8bd6-b5d61a13d73d"                           # a UUID
    "C:\Work\horde-worktrees\decisions2\test\fixtures\a-rather-long-file-name-for-a-fixture.json"   # cut at every separator: no piece is long
    "work/horde-worktrees/decisions/test/fixtures/another-rather-long-file-name-2-for-a-fixture.json"
    "A password is needed before this can be tested; it will be typed into the session."
    "token: none yet"
    "PASSWORD: ask whoever owns the test account"
    "The secret of the fix is that the timer runs in the app."
    "feature-decisions-store-first-slice-of-the-new-module"
    "ThisIsAVeryLongCamelCaseIdentifierWithNoDigitsAtAllInIt"
    ("word " * 20000)
)
$wrongly = @($ordinary | Where-Object { (Find-HordeDecisionSecretKind -Text $_) -ne "" })
Check ($wrongly.Count -eq 0) ("CONTROL: ordinary content is let through: a commit id, a UUID, long paths, the words password, token and secret in a sentence, long names, 100,000 characters of words (" + $wrongly.Count + " refused" + $(if ($wrongly.Count) { ": " + (@($wrongly | ForEach-Object { $_.Substring(0, [Math]::Min(40, $_.Length)) }) -join " | ") } else { "" }) + ")")
# THE STATED COST of favouring refusal (decisions/Rules.ps1): a long mixed-case name with a digit in it
# looks like a key and is refused too. Pinned here so that it is a decision, not a surprise.
Check ((Find-HordeDecisionSecretKind -Text "see AnotherRatherLongFileName2ForAFixtureOfThisSuite") -like "a long random-looking string*") "a 48-character mixed-case name with a digit is refused as random-looking: the stated cost of the threshold"

Write-Host ""
Write-Host "--- a request hashes by what it says, not how it was spelled ---" -ForegroundColor Cyan
$h1 = Get-HordeDecisionHash -Value ([ordered]@{ a = 1; b = "x"; c = @("p", "q") })
$h2 = Get-HordeDecisionHash -Value ('{"c":["p","q"],"b":"x","a":1}' | ConvertFrom-Json)
Check ($h1 -cmatch '\A[0-9a-f]{64}\z') "the hash is 64 lowercase hex digits"
Check ($h1 -ceq $h2) "key order does not change it, nor whether the value was a table or parsed JSON"
Check ($h1 -cne (Get-HordeDecisionHash -Value ([ordered]@{ a = 1; b = "y"; c = @("p", "q") }))) "a changed text changes it"
Check ($h1 -cne (Get-HordeDecisionHash -Value ([ordered]@{ a = 1; b = "x"; c = @("q", "p") }))) "a reordered list changes it: the order of options is part of the question"
Check ($h1 -ceq (Get-HordeDecisionHash -Value ('{"a":1.0,"b":"x","c":["p","q"]}' | ConvertFrom-Json))) "1 and 1.0 hash the same"
Check ((Get-HordeDecisionHash -Value @{ t = 'a"b' }) -cne (Get-HordeDecisionHash -Value @{ t = 'a\"b' })) "a quote and an escaped quote are different texts"
Check (Throws { Get-HordeDecisionHash -Value @{ when = (Get-Date) } } "cannot be hashed") "a value that is not JSON data is refused, never hashed as its type name"

Write-Host ""
Write-Host "--- the Nth question-added record is question N ---" -ForegroundColor Cyan
$records = @(
    (New-Added 1 1), (New-Added 2 2),
    (New-Record 3 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ recommendation = "yes, a short one" } })),
    (New-Added 4 3),
    (New-Record 5 "question-closed" ([ordered]@{ number = 2; outcome = "Built." })),
    (New-Added 6 4),
    (New-Record 7 "question-reopened" ([ordered]@{ number = 2; reason = "not finished" })),
    (New-Added 8 5)
)
$st = Get-Fold $records
Check ((Get-Numbers $st) -ceq "1,2,3,4,5") "five question-added records among eight are questions 1 to 5"
Check (@(1..5 | Where-Object { $st.questions[$_].title -cne "Is question number $_ asked in plain words here?" }).Count -eq 0) "and each number is the question added at that place"
Check ($st.lastSequence -eq 8 -and $st.lastNumber -eq 5 -and $st.unreadable.Count -eq 0 -and $st.ignored.Count -eq 0) "CONTROL: every record was read and applied"
Check ((Get-HordeDecisionNextNumber -State $st) -eq 6) "the next question would be 6"
# The number of a question never changes as records are added after it: fold every prefix.
$moved = New-Object System.Collections.ArrayList
for ($k = 1; $k -le $records.Count; $k++) {
    $part = Get-Fold @($records[0..($k - 1)])
    foreach ($num in @($part.questions.Keys)) { if ($part.questions[$num].title -cne $st.questions[$num].title) { [void]$moved.Add("after record " + $k + ": " + $num) } }
}
Check ($moved.Count -eq 0) "folding the first 1, 2, ... 8 records never gives any question another number than it ends with"

Write-Host ""
Write-Host "--- closing and reopening never move a number or free one ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Added 2 2), (New-Record 3 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })))
Check ($st.questions[1].state -ceq "closed" -and $st.questions[1].outcome -ceq "Done." -and $st.questions[1].closedAt -ne "") "a closed question is closed, with its outcome and when"
Check ((Get-HordeDecisionNextNumber -State $st) -eq 3) "a closed question's number is not given again: the next question is 3, not 1"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })), (New-Record 3 "question-reopened" ([ordered]@{ number = 1; reason = "it came back" })), (New-Added 4 2))
Check ($st.questions[1].state -ceq "open" -and $st.questions[1].outcome -eq "" -and $st.questions[1].closedAt -eq "" -and $st.questions[1].reopenReason -ceq "it came back") "a reopened question is open again under its own number, with the reason"
Check ((Get-Numbers $st) -ceq "1,2" -and $st.questions[1].history.Count -eq 3) "it is the same question: its history holds the add, the close and the reopen"
Check ((@($st.questions[1].history | ForEach-Object { $_.note }) -join ",") -ceq "added,closed,reopened") "in order"

Write-Host ""
Write-Host "--- a record that cannot apply is reported and changes nothing ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })), (New-Record 3 "question-closed" ([ordered]@{ number = 1; outcome = "Done again." })))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].sequence -eq 3 -and $st.ignored[0].reason -like "*already closed*" -and $st.questions[1].outcome -ceq "Done.") "a second close of a closed question is ignored by name; the first outcome stands"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-reopened" ([ordered]@{ number = 1; reason = "why" })))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*only a closed question can be reopened*") "reopening an open question is ignored by name"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })), (New-Record 3 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ title = "Should something else entirely be asked here?" } })))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*only an open question can be changed*" -and $st.questions[1].title -clike "Is question number 1*") "a change to a closed question is ignored by name, and its words stand"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 7; outcome = "Done." })))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*there is no question 7*") "a record about a number never given is ignored by name"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ group = "voice" } })))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*it changes nothing*" -and $st.questions[1].history.Count -eq 1) "a change that changes nothing is not a change: no history line, and it is reported"

Write-Host ""
Write-Host "--- the wording version counts changes to what a person reads ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1),
    (New-Record 2 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ recommendation = "yes"; waiting = @("orc-b"); files = @("a.txt"); group = "audio" } })),
    (New-Record 3 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ yesMeans = "A short tone plays." } })),
    (New-Record 4 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ kind = "choice"; options = @("tone", "spoken line") } })),
    (New-Record 5 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ title = "Which closing signal should play when the assistant closes?"; whatItIs = "The app has no closing sound today." } })))
$q = $st.questions[1]
Check ($st.ignored.Count -eq 0 -and $q.history.Count -eq 5) "CONTROL: all four changes applied"
Check ($q.history[1].note -ceq "changed recommendation, group, waiting, files") "a change to the recommendation, the group, who is waiting and the files is not a new wording"
Check ($q.history[2].note -ceq "changed yesMeans (now wording 2)") "a change to yesMeans is wording 2"
Check ($q.history[3].note -ceq "changed kind, options (now wording 3)") "a change to the options is wording 3"
Check ($q.history[4].note -ceq "changed title (now wording 4)" -and $q.wordingVersion -eq 4) "a change to the title is wording 4, and a field given its old value is not counted as changed"
Check ($q.group -ceq "audio" -and (@($q.options) -join "|") -ceq "tone|spoken line" -and $q.kind -ceq "choice") "and the question holds the latest value of every field"

Write-Host ""
Write-Host "--- an unreadable record never stops the list and never renumbers a question ---" -ForegroundColor Cyan
# Record 2 cannot be read. Questions added AFTER it wrote their numbers down, so whether record 2 was a
# question or not, they keep them.
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Added 3 2), (New-Added 4 3))
Check ((Get-Numbers $st) -ceq "1,2,3" -and $st.unreadable.Count -eq 1 -and $st.unreadable[0].sequence -eq 2 -and $st.unreadable[0].file -ceq "0000000002.json") "the list loads around a torn record, which is named with its file"
Check ($st.unreadable[0].reason -like "*not complete JSON*") "and its reason is the store's"
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Added 3 3), (New-Added 4 4))
Check ((Get-Numbers $st) -ceq "1,3,4") "when the torn record was question 2, questions 3 and 4 are still 3 and 4: nothing shifts down into the gap"
Check ((Get-HordeDecisionNumberStatus -State $st -Number 2) -ceq "unreadable" -and (Get-HordeDecisionNumberStatus -State $st -Number 3) -ceq "present" -and (Get-HordeDecisionNumberStatus -State $st -Number 5) -ceq "absent") "number 2 is known to be unreadable, not absent; 5 was never given"
Check ((Get-HordeDecisionNextNumber -State $st) -eq 5) "CONTROL: with every later record readable, the next number is 5"
# At the END of the order nothing later says what an unreadable record was, so its number is left unused.
$st = Get-Fold @((New-Added 1 1), (New-Added 2 2), (New-Torn 3))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 4) "after an unreadable last record the next question is 4, not 3: the record may have been question 3"
Check ((Get-HordeDecisionNumberStatus -State $st -Number 3) -ceq "unreadable") "and number 3 reads as unreadable meanwhile"
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Torn 3), (New-Record 4 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 4 -and $st.questions[1].state -ceq "closed") "two unreadable records leave two numbers unused, and a readable record after them still applies"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-updated" ([ordered]@{ number = 2; changes = [ordered]@{ group = "x" } })), (New-Torn 3))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*there is no question 2*") "CONTROL: a record about a number above every number given is about no question"
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Record 3 "question-closed" ([ordered]@{ number = 2; outcome = "Done." })))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*whose own record cannot be read*") "a record about a question whose own record is unreadable says exactly that"

# A GAP IS ONE ENTRY THAT COVERS SEVERAL NUMBERS (decisions/Store.ps1 hands it over with a span). Any of
# the records it covers may have been a question, so it costs a question number for each, and it is
# reported once.
function New-Gap { param([long]$Seq, [long]$Span) return [pscustomobject]@{ sequence = $Seq; span = $Span; file = ($Seq.ToString("D10") + ".json"); kind = "missing"; data = $null; reason = ("records " + $Seq + " to " + ($Seq + $Span - 1) + " are not in the store folder") } }
$st = Get-Fold @((New-Added 1 1), (New-Gap 2 3), (New-Added 5 5))
Check ((Get-Numbers $st) -ceq "1,5" -and $st.unreadable.Count -eq 1 -and $st.unreadable[0].sequence -eq 2 -and $st.unreadable[0].reason -like "*records 2 to 4*") "a gap of three records is reported ONCE, from where to where, and the list loads around it"
$st = Get-Fold @((New-Added 1 1), (New-Gap 2 3))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 5) ("three missing records at the end leave three numbers unused: the next question is 5 (" + (Get-HordeDecisionNextNumber -State $st) + ")")
Check ($st.lastSequence -eq 4) ("and the order ends at record 4, the last the gap covers (" + $st.lastSequence + ")")
Check ((Get-HordeDecisionNumberStatus -State $st -Number 4) -ceq "unreadable" -and (Get-HordeDecisionNumberStatus -State $st -Number 5) -ceq "absent") "numbers 2 to 4 read as unreadable, and 5 as never given"

Write-Host ""
Write-Host "--- a record that contradicts the order is not believed ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Added 2 2), (New-Added 3 2 "Is this second claim to number two shown at all?"))
Check ((Get-Numbers $st) -ceq "1,2" -and $st.questions[2].title -clike "Is question number 2*") "a later record claiming a number already given does not replace that question"
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].sequence -eq 3 -and $st.ignored[0].reason -like "*a number is never given twice*") "it is reported by name"
Check ((Get-HordeDecisionNextNumber -State $st) -eq 4) "and its place is counted when the next number is worked out, so the next question is 4"

Write-Host ""
Write-Host "--- a record of the wrong shape is unreadable, with the reason ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-added" ([ordered]@{ number = 2; question = (ConvertTo-HordeDecisionFields -Source (New-Question)) }) -Version 2), (New-Added 3 3))
Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*not a decision-event.v1 record*schemaVersion*" -and (Get-Numbers $st) -ceq "1,3") "a record of schema version 2 is not read as version 1: it is unreadable, and says which field"
# A KIND THIS VERSION DOES NOT KNOW is not damage: see "a record of a later kind" below.
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1 })))
Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*its data is not what a question-closed record holds*outcome*" -and $st.questions[1].state -ceq "open") "a close with no outcome is unreadable, and the question stays open"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ title = 5 } })))
Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*changes.title should be string*") "a change whose title is not text is unreadable: the words inside a record are checked too"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-updated" ([ordered]@{ number = 1; changes = [ordered]@{ colour = "red" } })))
Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*colour*") "and so is one naming a field a question does not have"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." }) -SaysSeq 5))
Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*it says it is record 5*" -and $st.questions[1].state -ceq "open") "a record that says it is record 5 in the place of record 2 is unreadable"
$long400 = [pscustomobject]@{ sequence = [long]2; file = "0000000002.json"; kind = "error"; data = $null; reason = ("r" * 900) }
$st = Get-Fold @((New-Added 1 1), $long400)
Check ($st.unreadable[0].reason.Length -lt 450 -and $st.unreadable[0].reason -like "*reason cut at 400 characters*") "a very long reason is cut, and says it was"

Write-Host ""
Write-Host "--- a number too large to be one never stops the list ---" -ForegroundColor Cyan
# A record that is well-formed JSON and passes "type": "integer" can still hold a number no question
# or record can have. Measured 2026-10-06, before the limits in decisions/Rules.ps1: one such record in
# the store made list, show and add throw "Cannot convert value 99999999999 to type System.Int32" -
# the whole list unloadable for one bad record. These are built as JSON text, as the store reads them,
# because 1e30 has no spelling as a PowerShell whole number.
function New-RawRecord {
    param([long]$Seq, [string]$SaysSeq, [string]$Kind, [string]$DataJson)
    $json = '{"schemaVersion":1,"sequence":' + $SaysSeq + ',"id":"' + $Seq.ToString("x32") + '","kind":"' + $Kind + '","at":"2026-10-06T12:00:00.0000000Z","actor":"warchief","requestHash":"' + $zeros + '","data":' + $DataJson + '}'
    return [pscustomobject]@{ sequence = $Seq; file = ($Seq.ToString("D10") + ".json"); kind = "ok"; data = ($json | ConvertFrom-Json); reason = "" }
}
$wordsJson = ConvertTo-Json -InputObject (ConvertTo-HordeDecisionFields -Source (New-Question)) -Compress
foreach ($huge in @("99999999999", "1e30", "1000000000")) {
    $st = Get-Fold @((New-Added 1 1), (New-RawRecord 2 "2" "question-added" ('{"number":' + $huge + ',"question":' + $wordsJson + '}')), (New-Added 3 3))
    Check ((Get-Numbers $st) -ceq "1,3" -and $st.unreadable.Count -eq 1 -and $st.unreadable[0].sequence -eq 2 -and $st.unreadable[0].reason -like "*question number*999999999*") ("a question-added record numbered " + $huge + " is unreadable, by name, and questions 1 and 3 are still listed")
    Check ((Get-HordeDecisionNextNumber -State $st) -eq 4) "and the next question is 4: the record did not move the numbering"
}
$st = Get-Fold @((New-Added 1 1), (New-RawRecord 2 "2" "question-closed" '{"number":99999999999,"outcome":"Done."}'), (New-Added 3 2))
Check ((Get-Numbers $st) -ceq "1,2" -and $st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*question number*" -and $st.questions[1].state -ceq "open") "a close of question 99999999999 is unreadable too, and the list loads"
$st = Get-Fold @((New-Added 1 1), (New-RawRecord 2 "1e30" "question-closed" '{"number":1,"outcome":"Done."}'), (New-Added 3 2))
Check ((Get-Numbers $st) -ceq "1,2" -and $st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*sequence number*9999999999*" -and $st.questions[1].state -ceq "open") "a record that says its sequence number is 1e30 is unreadable, and the list loads"
$st = Get-Fold @((New-Added 1 1), (New-RawRecord 2 "2" "question-added" ('{"number":999999999,"question":' + $wordsJson + '}')))
Check ((Get-Numbers $st) -ceq "1,999999999" -and $st.unreadable.Count -eq 0) "CONTROL: 999999999 is the largest number a question can have, and a record holding it is read"
Check ((Get-HordeDecisionMaxNumber) -eq 999999999) "CONTROL: the limit the rules give out is that number"

Write-Host ""
Write-Host "--- a record by an actor this version does not list is still a record ---" -ForegroundColor Cyan
# A stored record is a fact. Who MAY write is asked of a request, before it is written; a record that
# a later version wrote, under an actor added since, must not become unreadable here and cost a number.
$byAnother = New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Answered and done." })
$byAnother.data.actor = "founder"
$st = Get-Fold @((New-Added 1 1), $byAnother, (New-Added 3 2))
Check ($st.unreadable.Count -eq 0 -and $st.questions[1].state -ceq "closed" -and (Get-Numbers $st) -ceq "1,2") ("a close recorded by an actor outside this version's list is read and applied (" + $st.unreadable.Count + " unreadable)")
Check ($st.questions[1].history.Count -eq 2 -and $st.questions[1].history[1].actor -ceq "founder") "and the history says who it was"
foreach ($badActor in @("", "Two Words", "UPPER", "line`nbreak")) {
    $odd = New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })
    $odd.data.actor = $badActor
    $st = Get-Fold @((New-Added 1 1), $odd)
    Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].reason -like "*actor*" -and $st.questions[1].state -ceq "open") ("CONTROL: an actor that is not one lowercase label ('" + ($badActor -replace "`n", "\n") + "') is still the wrong shape, and that record is unreadable")
}

Write-Host ""
Write-Host "--- a record of a later kind is set aside: not understood, and never a possible question ---" -ForegroundColor Cyan
# THE COMPATIBILITY CONTRACT (decisions/Rules.ps1): a record whose envelope is well formed and whose
# kind this version does not know was written by a later version. It cannot have been a question -
# "question-added" is a kind every version knows, and a kind's name never changes meaning - so it
# costs no question number. Measured 2026-10-07, before this was the rule: one such record between two
# questions made the next question 4 instead of 3, and a store with a hundred of them would have
# left a hundred numbers unused.
function Get-NotUnderstood { param($State) if ($null -eq $State.PSObject.Properties["notUnderstood"]) { return "(the list keeps no such thing)" }; return (@($State.notUnderstood.Values | ForEach-Object { "" + $_.kind + " x" + $_.count + " " + $_.first + "-" + $_.last }) -join "; ") }
$later = @(
    (New-Added 1 1),
    (New-Record 2 "seen-by-founder" ([ordered]@{ upTo = 1 })),
    (New-Record 3 "answer-recorded" ([ordered]@{ number = 1; words = "yes" })),
    (New-Added 4 2),
    (New-Record 5 "answer-recorded" ([ordered]@{ number = 2; words = "no"; anything = @{ at = "all" } })),
    (New-Record 6 "answer-recorded" ([ordered]@{ number = 2 }))
)
$st = Get-Fold $later
Check ((Get-Numbers $st) -ceq "1,2") ("with four records of two later kinds among them, the questions are 1 and 2 (" + (Get-Numbers $st) + ")")
Check ((Get-HordeDecisionNextNumber -State $st) -eq 3) ("and the next question is 3: a record of a later kind leaves no number unused (" + (Get-HordeDecisionNextNumber -State $st) + ")")
Check ($st.unreadable.Count -eq 0 -and $st.ignored.Count -eq 0) ("none of them is reported as unreadable or as not applying: they are not damage (" + $st.unreadable.Count + " unreadable)")
Check ((Get-NotUnderstood $st) -ceq "seen-by-founder x1 2-2; answer-recorded x3 3-6") ("they are set aside by kind, each kind once, with how many and from which record to which (" + (Get-NotUnderstood $st) + ")")
Check ($st.lastSequence -eq 6 -and $st.questions[1].state -ceq "open" -and @($st.questions[1].history).Count -eq 1) "the order still runs to record 6, and no question was changed by a record this version cannot read the meaning of"
# Every prefix: at no point does a later-kind record move a number.
$moved = New-Object System.Collections.ArrayList
for ($i = 1; $i -le $later.Count; $i++) { $part = Get-Fold @($later[0..($i - 1)]); $want = 2; if ($i -ge 4) { $want = 3 }; if ((Get-HordeDecisionNextNumber -State $part) -ne $want) { [void]$moved.Add("after record " + $i + ": " + (Get-HordeDecisionNextNumber -State $part)) } }
Check ($moved.Count -eq 0) ("after every record of that history the next number is what it would be without them" + $(if ($moved.Count) { " (" + ($moved -join "; ") + ")" } else { "" }))
# ITS ID IS STILL SEEN: the envelope is readable, so a repost of that id is known to have been recorded.
$laterId = ([long]3).ToString("x32")
Check ($st.ids.ContainsKey($laterId) -and $st.ids[$laterId].sequence -eq 3 -and $st.ids[$laterId].kind -ceq "answer-recorded" -and $st.ids[$laterId].applied -eq $false -and $st.ids.Count -eq 6) "the list knows the id of a record it did not understand, with its record and its kind"
# CONTROL: DAMAGE KEEPS THE CONSERVATIVE RULE. A record that cannot be read at all, or whose envelope is
# not this schema's, may have been a question, and still leaves a number unused.
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Added 3 3))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 4 -and $st.unreadable.Count -eq 1 -and (Get-NotUnderstood $st) -ceq "") "CONTROL: a torn record is still unreadable and still costs a number: it may have been a question"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "answer-recorded" ([ordered]@{ number = 1 }) -Version 2))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 3 -and $st.unreadable.Count -eq 1 -and (Get-NotUnderstood $st) -ceq "") "CONTROL: a later kind in an envelope that is not this schema's is unreadable, not set aside: nothing about it can be trusted"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "answer-recorded" ([ordered]@{ number = 1 }) -SaysSeq 7))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 3 -and $st.unreadable.Count -eq 1 -and (Get-NotUnderstood $st) -ceq "") "CONTROL: a later kind that says it is another record than its place is unreadable, not set aside"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-added" ([ordered]@{ number = 2 })))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 3 -and $st.unreadable.Count -eq 1 -and (Get-NotUnderstood $st) -ceq "") "CONTROL: a KNOWN kind with data that is not its own is damage, as before"
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "Answer Recorded" ([ordered]@{ number = 1 })))
Check ($st.unreadable.Count -eq 1 -and (Get-NotUnderstood $st) -ceq "") "CONTROL: a kind that is not a kind's name at all fails the envelope, and is unreadable"
# A NUMBER IS NEVER GIVEN TWICE, EVEN WHEN A KIND'S NAME IS DAMAGED. A question-added record whose kind
# is damaged into another well-formed name is set aside as a later kind. Observed in review on
# 2026-10-07: its question number was then given to the next question. So a set-aside record's number
# field, when it is shaped like a question number, still raises the floor: the next question is above it.
$damaged = New-Added 2 2
$damaged.data.kind = "question-addex"
$st = Get-Fold @((New-Added 1 1), $damaged)
Check ((Get-NotUnderstood $st) -ceq "question-addex x1 2-2" -and $st.unreadable.Count -eq 0) ("a question-added record with its kind damaged to another name is set aside as a later kind (" + (Get-NotUnderstood $st) + ")")
Check ((Get-HordeDecisionNextNumber -State $st) -eq 3) ("and the next question is 3, not 2: the number it carries is never given again (" + (Get-HordeDecisionNextNumber -State $st) + ")")
Check ((Get-HordeDecisionNumberStatus -State $st -Number 2) -ceq "unreadable") ("and number 2 is a number that was given and cannot be shown, not one never given (" + (Get-HordeDecisionNumberStatus -State $st -Number 2) + ")")
$st = Get-Fold @((New-Added 1 1), $damaged, (New-Added 3 2 "Is question number two given twice when a kind is damaged?"))
Check ((Get-Numbers $st) -ceq "1" -and $st.ignored.Count -eq 1 -and "$($st.ignored[0].reason)" -like "*a number is never given twice*") ("a later record that says it is question 2 is not shown, and says why: number 2 was already given (" + (Get-Numbers $st) + ")")
# A later kind's number field only ever RAISES the floor; one at or below it moves nothing, and one that
# is not shaped like a question number is not read as one.
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Torn 3), (New-Record 4 "answer-recorded" ([ordered]@{ number = 2 })))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 4) ("CONTROL: a later kind's number below the next one moves nothing - it never lowers the floor two unreadable records raised (" + (Get-HordeDecisionNextNumber -State $st) + ")")
$st = Get-Fold @((New-Added 1 1), (New-Torn 2), (New-Record 3 "answer-recorded" ([ordered]@{ number = 5 })))
Check ((Get-HordeDecisionNextNumber -State $st) -eq 6) ("a later kind's number above the floor is the new floor, as a question-added's would be: the unreadable record before it is counted in it (" + (Get-HordeDecisionNextNumber -State $st) + ")")
foreach ($odd in @(0, -4, 2.5, "7", 1e30)) {
    $st = Get-Fold @((New-Added 1 1), (New-Record 2 "answer-recorded" ([ordered]@{ number = $odd })))
    Check ((Get-HordeDecisionNextNumber -State $st) -eq 2) ("CONTROL: a number field of " + $odd + " is not a question number, and moves nothing (" + (Get-HordeDecisionNextNumber -State $st) + ")")
}

Write-Host ""
Write-Host "--- one id, one record to answer from ---" -ForegroundColor Cyan
$sameId = "ab" * 16
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." }) -Id $sameId), (New-Record 3 "question-reopened" ([ordered]@{ number = 1; reason = "again" }) -Id $sameId))
Check ($st.ids[$sameId].sequence -eq 2 -and $st.ids[$sameId].kind -ceq "question-closed") "when two records carry one id, the first is the one a repost is answered from"
Check ($st.ids.Count -eq 2 -and $st.ids[$sameId].number -eq 1 -and $st.ids[$sameId].applied -eq $true) "CONTROL: the list knows each id's record, its question and that it applied"

function New-Said {
    # A message-said record. The envelope's actor is who made the request, which for words recorded
    # from chat is not the speaker.
    param([long]$Seq, [int]$Number, [string]$Speaker = "founder", [string]$Route = "chat-recorded", [string]$Text = "Yes, do it.", $Wording = 1, [string]$Actor = "warchief")
    $record = New-Record -Seq $Seq -Kind "message-said" -Data ([ordered]@{ number = $Number; speaker = $Speaker; route = $Route; text = $Text; wordingVersion = $Wording })
    $record.data.actor = $Actor
    return $record
}
function New-Reply { param([long]$Seq, [int]$Number, [string]$Text = "Done as you said.", $Wording = 1) return (New-Said -Seq $Seq -Number $Number -Speaker "warchief" -Route "command" -Text $Text -Wording $Wording) }
function New-Read { param([long]$Seq, $UpTo, [string]$Reader = "warchief") return (New-Record -Seq $Seq -Kind "messages-read" -Data ([ordered]@{ reader = $Reader; upTo = $UpTo })) }
function New-Closed { param([long]$Seq, [int]$Number) return (New-Record -Seq $Seq -Kind "question-closed" -Data ([ordered]@{ number = $Number; outcome = "Done." })) }
function New-Reopened { param([long]$Seq, [int]$Number) return (New-Record -Seq $Seq -Kind "question-reopened" -Data ([ordered]@{ number = $Number; reason = "it came back" })) }
function New-Reworded { param([long]$Seq, [int]$Number, [string]$Title) return (New-Record -Seq $Seq -Kind "question-updated" -Data ([ordered]@{ number = $Number; changes = @{ title = $Title } })) }
function Get-Thread {
    # A question's thread as it is shown, messages included; a throw becomes a thread of -1 messages.
    param($State, [int]$Number = 1)
    try { return (ConvertTo-HordeDecisionThreadView -Question $State.questions[$Number] -State $State -Messages) } catch { return [pscustomobject]@{ count = -1; turn = ("THREW: " + $_.Exception.Message); turnShown = ""; unread = @(); messages = @() } }
}
function Get-Unread { param($Thread, [string]$Reader = "warchief") $u = @($Thread.unread | Where-Object { $_.reader -ceq $Reader }) | Select-Object -First 1; if ($null -eq $u) { return -1 }; return [int]$u.count }
function Get-Texts { param($Thread) return (@($Thread.messages | ForEach-Object { $_.text }) -join " | ") }

Write-Host ""
Write-Host "--- a thread is its messages in store order, and speaking changes nothing of the question ---" -ForegroundColor Cyan
$before = Get-Fold @((New-Added 1 1), (New-Added 2 2))
$st = Get-Fold @((New-Added 1 1), (New-Added 2 2), (New-Said 3 1 -Text "first"), (New-Said 4 2 -Text "to the other question"), (New-Said 5 1 -Text "second"), (New-Reply 6 1 -Text "third, a reply"))
$t = Get-Thread $st 1
Check ($t.count -eq 3 -and (Get-Texts $t) -ceq "first | second | third, a reply" -and (@($t.messages | ForEach-Object { $_.sequence }) -join ",") -ceq "3,5,6") ("question 1's thread is its three messages, in the order of their records (" + (Get-Texts $t) + ")")
Check ((Get-Thread $st 2).count -eq 1 -and (Get-Texts (Get-Thread $st 2)) -ceq "to the other question") "and question 2's is its own one: two messages to one question are both kept, and none strays to another"
Check ($st.unreadable.Count -eq 0 -and $st.ignored.Count -eq 0) "nothing was unreadable and nothing was ignored"
$same = $true
foreach ($n in 1, 2) {
    $was = ConvertTo-HordeDecisionView -Question $before.questions[$n] -State $before
    $is = ConvertTo-HordeDecisionView -Question $st.questions[$n] -State $st
    foreach ($member in @($was.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $_ -cne "thread" })) {
        if ((ConvertTo-Json -InputObject $was.$member -Compress -Depth 6) -cne (ConvertTo-Json -InputObject $is.$member -Compress -Depth 6)) { $same = $false; Write-Host ("         question " + $n + ": '" + $member + "' changed") -ForegroundColor Red }
    }
}
Check $same "speaking changed nothing else of either question: not its number, its state, its wording, its history, nor when it was last changed"
Check ((Get-Numbers $st) -ceq "1,2" -and (Get-HordeDecisionNextNumber -State $st) -eq 3) "and no number moved: the next question is still 3"
$m = $t.messages[0]
Check ($m.speaker -ceq "founder" -and $m.speakerShown -ceq "the founder" -and $m.route -ceq "chat-recorded" -and $m.routeShown -ceq "recorded by the warchief from chat" -and $m.recordedBy -ceq "warchief") "words the warchief wrote down from chat are the founder's words, stored and shown as recorded by the warchief from chat"
$typed = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Route "window" -Actor "founder" -Text "typed by him"))
$m = (Get-Thread $typed 1).messages[0]
Check ($m.route -ceq "window" -and $m.routeShown -ceq "typed in the window" -and $m.recordedBy -ceq "founder" -and $m.routeShown -cne "recorded by the warchief from chat") "words he typed himself are another route, shown in other words: the two are never one"
# VERBATIM: what the record holds is what the thread holds, character for character.
$exact = "  leading spaces, a tab`there, a line`r`nand another`nand a last one with trailing spaces  `r`n`r`n"
$dateLike = "/Date(1234567890)/"
$st = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Text $exact), (New-Said 3 1 -Text $dateLike), (New-Said 4 1 -Text "0012"), (New-Said 5 1 -Text "true"))
$t = Get-Thread $st 1
Check ($t.count -eq 4 -and [string]::Equals($t.messages[0].text, $exact, [System.StringComparison]::Ordinal)) "words with leading and trailing spaces, a tab, and line breaks of both kinds come back exactly: nothing trimmed, nothing re-wrapped"
Check ($t.count -eq 4 -and $t.messages[1].text -is [string] -and $t.messages[1].text -ceq $dateLike -and $t.messages[2].text -is [string] -and $t.messages[2].text -ceq "0012" -and $t.messages[3].text -is [string] -and $t.messages[3].text -ceq "true") "words that look like a date, a number or a flag stay the words they are"

Write-Host ""
Write-Host "--- whose turn it is, through a whole exchange: derived at every step, stored nowhere ---" -ForegroundColor Cyan
$exchange = @(
    (New-Added 1 1),                                    # asked: the founder's turn
    (New-Said 2 1 -Text "which one?"),                  # he speaks: the warchief's
    (New-Said 3 1 -Text "and by when?"),                # he speaks again: still the warchief's
    (New-Reply 4 1 -Text "the first; by Friday"),       # it replies: the founder's
    (New-Reworded 5 1 "Should the first closing sound play by Friday?"),   # a rewording takes no turn
    (New-Said 6 1 -Text "yes" -Wording 2),              # he speaks: the warchief's
    (New-Closed 7 1),                                   # it closes instead of replying: nobody's
    (New-Said 8 1 -Text "wait" -Wording 2),             # he speaks under a closed question: still nobody's
    (New-Reopened 9 1),                                 # asked again: the founder's
    (New-Reply 10 1 -Text "reopened for you" -Wording 2),   # it speaks first: still the founder's
    (New-Said 11 1 -Text "thanks, yes" -Wording 2)      # he speaks: the warchief's
)
$turns = New-Object System.Collections.ArrayList
for ($i = 1; $i -le $exchange.Count; $i++) { [void]$turns.Add((Get-Thread (Get-Fold @($exchange[0..($i - 1)])) 1).turn) }
Check (($turns -join ",") -ceq "founder,warchief,warchief,founder,founder,warchief,nobody,nobody,founder,founder,warchief") ("after each record of the exchange the turn is whose it should be (" + ($turns -join ",") + ")")
$st = Get-Fold $exchange
$t = Get-Thread $st 1
Check ($t.turnShown -ceq "the warchief" -and (Get-Thread (Get-Fold @($exchange[0..6])) 1).turnShown -ceq "nobody" -and (Get-Thread (Get-Fold @($exchange[0..0])) 1).turnShown -ceq "the founder") "and it is told to a person in words: the founder, the warchief, nobody"
Check ($t.count -eq 7 -and $st.questions[1].state -ceq "open" -and $st.ignored.Count -eq 0 -and $st.unreadable.Count -eq 0) "all seven messages of the exchange are in the thread, the one said while it was closed among them"
Check ($null -eq $st.questions[1].thread[0].PSObject.Properties["turn"] -and @($exchange | Where-Object { $null -ne $_.data.data.PSObject.Properties["turn"] -or $null -ne $_.data.data.PSObject.Properties["unread"] -or $null -ne $_.data.data.PSObject.Properties["arrivedAfterClosing"] -or $null -ne $_.data.data.PSObject.Properties["saidToEarlierWording"] }).Count -eq 0) "CONTROL: no record of the exchange holds a turn, a flag or what is unread: they were worked out"
# A speaker this version does not list (a later version wrote the record) is read and shown, and takes no turn.
$st = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Text "first"), (New-Said 3 1 -Speaker "orc" -Route "relay" -Text "from a later version"))
$t = Get-Thread $st 1
Check ($t.count -eq 2 -and $t.messages[1].speakerShown -ceq "orc" -and $t.messages[1].routeShown -ceq "relay" -and $t.turn -ceq "warchief" -and $st.unreadable.Count -eq 0 -and $st.ignored.Count -eq 0) "a message by a speaker and a route this version does not list is still read and shown by their names, and the turn stays where it was"

Write-Host ""
Write-Host "--- words under a closed question are kept, flagged, and reopen nothing ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Text "said while open"), (New-Closed 3 1), (New-Said 4 1 -Text "said a moment too late"), (New-Said 5 1 -Text "and once more"))
$t = Get-Thread $st 1
Check ($t.count -eq 3 -and (Get-Texts $t) -ceq "said while open | said a moment too late | and once more") "every word said under a closed question is in its thread: none is dropped"
Check ((@($t.messages | ForEach-Object { $_.arrivedAfterClosing }) -join ",") -ceq "False,True,True") "the ones that arrived after closing are flagged, and the one said while it was open is not"
Check ($st.questions[1].state -ceq "closed" -and $st.questions[1].outcome -ceq "Done." -and @($st.questions[1].history).Count -eq 2 -and $t.turn -ceq "nobody") "and the question is still closed, with its outcome and a history of two: saying something reopened nothing"
Check ($st.ignored.Count -eq 0 -and $st.unreadable.Count -eq 0) "they are not reported as records that did not apply: they applied"
$st = Get-Fold @((New-Added 1 1), (New-Closed 2 1), (New-Said 3 1 -Text "late"), (New-Reopened 4 1), (New-Said 5 1 -Text "after it came back"))
$t = Get-Thread $st 1
Check ((@($t.messages | ForEach-Object { $_.arrivedAfterClosing }) -join ",") -ceq "True,False") "a message that arrived after closing stays flagged when the question is reopened later, and one said after the reopening is not flagged"

Write-Host ""
Write-Host "--- words said to an earlier wording are kept and flagged ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Reworded 2 1 "Should the closing sound play at the end of every session?"), (New-Said 3 1 -Text "to the old words" -Wording 1), (New-Said 4 1 -Text "to the new words" -Wording 2))
$t = Get-Thread $st 1
Check ($st.questions[1].wordingVersion -eq 2 -and $t.count -eq 2) "CONTROL: the question is at wording 2, and both messages are in its thread"
Check ((@($t.messages | ForEach-Object { "" + $_.wordingVersion + ":" + $_.saidToEarlierWording }) -join ",") -ceq "1:True,2:False") "the message said to wording 1 is flagged as said to an earlier wording; the one said to wording 2 is not"
# JUDGED AT THE MOMENT THE WORDS WERE SAID, in store order - never against today's wording. Words said to
# the wording the question had are not flagged, and a LATER rewording does not flag them: he answered
# the question as it read. In both directions:
$history = @((New-Added 1 1), (New-Said 2 1 -Text "yes, to the first wording" -Wording 1), (New-Reworded 3 1 "Should the closing sound play at the end of every session?"), (New-Said 4 1 -Text "still to the first wording" -Wording 1), (New-Said 5 1 -Text "to the second" -Wording 2), (New-Reworded 6 1 "Should a closing sound play at the end of every session, and how long?"), (New-Said 7 1 -Text "to the second, now old" -Wording 2), (New-Said 8 1 -Text "to the third" -Wording 3))
$st = Get-Fold $history
$t = Get-Thread $st 1
Check ($st.questions[1].wordingVersion -eq 3 -and $t.count -eq 5) "CONTROL: the question has been reworded twice and is at wording 3, with five messages"
Check ((@($t.messages | ForEach-Object { "" + $_.sequence + ":" + $_.wordingVersion + ":" + $_.saidToEarlierWording }) -join ",") -ceq "2:1:False,4:1:True,5:2:False,7:2:True,8:3:False") ("each message is flagged by the wording the question had WHEN IT WAS SAID: the two said to the wording of their moment are not flagged though the question was reworded afterwards, and the two said to a wording already left are (" + (@($t.messages | ForEach-Object { "" + $_.sequence + ":" + $_.wordingVersion + ":" + $_.saidToEarlierWording }) -join ",") + ")")
$flags = New-Object System.Collections.ArrayList
for ($i = 2; $i -le $history.Count; $i++) { [void]$flags.Add("" + (Get-Thread (Get-Fold @($history[0..($i - 1)])) 1).messages[0].saidToEarlierWording) }
Check (($flags -join ",") -ceq "False,False,False,False,False,False,False") ("and the first message's flag never changes as the history grows: a later rewording does not reach back (" + ($flags -join ",") + ")")
# A wording that does not exist yet cannot have been looked at.
$st = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Text "to a wording from the future" -Wording 2), (New-Said 3 1 -Text "to the real one" -Wording 1))
Check ((Get-Thread $st 1).count -eq 1 -and $st.ignored.Count -eq 1 -and $st.ignored[0].sequence -eq 2 -and $st.ignored[0].reason -like "*said to wording 2 of question 1, which has only reached wording 1*") "a record claiming a wording the question had not reached is reported as not applying, by name, and is not shown as said"
Check ((Get-Thread $st 1).turn -ceq "warchief" -and $st.ignored[0].reason -cnotlike "*from the future*") "the next message is kept all the same, and the report does not repeat the words"

Write-Host ""
Write-Host "--- what the warchief has not read is worked out from its read mark ---" -ForegroundColor Cyan
$said = @((New-Added 1 1), (New-Added 2 2), (New-Said 3 1 -Text "one"), (New-Reply 4 1 -Text "its own reply"), (New-Said 5 2 -Text "two"), (New-Said 6 1 -Text "three"))
$st = Get-Fold $said
Check ((Get-Unread (Get-Thread $st 1)) -eq 2 -and (Get-Unread (Get-Thread $st 2)) -eq 1 -and (Get-HordeDecisionReadMark -State $st -Reader "warchief") -eq 0) "with no read mark, every message by someone else is unread by the warchief: two under question 1, one under question 2"
Check ((@((Get-Thread $st 1).messages | ForEach-Object { ($_.unreadBy -join "+") }) -join ",") -ceq "warchief,,warchief") "its own reply is never unread by it"
$st = Get-Fold ($said + @((New-Read 7 5)))
Check ((Get-Unread (Get-Thread $st 1)) -eq 1 -and (Get-Unread (Get-Thread $st 2)) -eq 0 -and (Get-HordeDecisionReadMark -State $st -Reader "warchief") -eq 5) "a mark up to record 5 leaves exactly the message after it unread: record 6"
Check ((@((Get-Thread $st 1).messages | ForEach-Object { ($_.unreadBy -join "+") }) -join ",") -ceq ",,warchief" -and $st.ignored.Count -eq 0) "and each message says for itself whether it has been read"
$st = Get-Fold ($said + @((New-Read 7 5), (New-Read 8 6)))
Check ((Get-Unread (Get-Thread $st 1)) -eq 0 -and (Get-Unread (Get-Thread $st 2)) -eq 0) "a mark up to the last message leaves nothing unread"
$st = Get-Fold ($said + @((New-Read 7 5), (New-Read 8 6), (New-Said 9 2 -Text "four")))
Check ((Get-Unread (Get-Thread $st 2)) -eq 1 -and (Get-Unread (Get-Thread $st 1)) -eq 0) "and a message said after the mark is unread again"
# A MARKING IS IDEMPOTENT: one that moves nothing changes nothing, and says so.
$st = Get-Fold ($said + @((New-Read 7 5), (New-Read 8 5), (New-Read 9 3)))
Check ((Get-HordeDecisionReadMark -State $st -Reader "warchief") -eq 5 -and $st.ignored.Count -eq 2 -and $st.ignored[0].sequence -eq 8 -and $st.ignored[0].reason -like "*marks nothing as read*already read up to record 5*") "the same mark again, and an earlier one, move nothing: the mark never goes back, and each is reported as changing nothing"
Check ($st.readEvents.Count -eq 1 -and $st.readEvents[[long]7].from -eq 0 -and $st.readEvents[[long]7].upTo -eq 5) "CONTROL: the one marking that applied is known by its record, with where the reader was before it"
# Nothing is read before it is written.
$st = Get-Fold ($said + @((New-Read 7 7), (New-Read 8 99)))
Check ((Get-HordeDecisionReadMark -State $st -Reader "warchief") -eq 0 -and $st.ignored.Count -eq 2 -and $st.ignored[0].reason -like "*not before this record*" -and (Get-Unread (Get-Thread $st 1)) -eq 2) "a mark that claims its own record, or one that does not exist yet, is not believed: nothing is marked read by it"
$st = Get-Fold ($said + @((New-Read 7 6), (New-Said 8 1 -Text "after")))
Check ((Get-Unread (Get-Thread $st 1)) -eq 1) "CONTROL: a mark up to the record just before its own is believed"
# Readers are apart: one's mark is not another's.
$st = Get-Fold ($said + @((New-Read 7 6 -Reader "founder")))
Check ((Get-HordeDecisionReadMark -State $st -Reader "founder") -eq 6 -and (Get-HordeDecisionReadMark -State $st -Reader "warchief") -eq 0 -and (Get-Unread (Get-Thread $st 1)) -eq 2) "a mark of another reader moves that reader's mark only: the warchief has still read nothing"

Write-Host ""
Write-Host "--- what a reader is to read: every question, oldest first, between two records ---" -ForegroundColor Cyan
$st = Get-Fold $said
function Get-ForSequences { param($Items) return (@($Items | ForEach-Object { "" + $_.message.sequence + "@" + $_.question.number }) -join ",") }
Check ((Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief")) -ceq "3@1,5@2,6@1") ("the warchief's unread messages come from every question, in the order they were said (" + (Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief")) + ")")
Check ((Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief" -UpTo 5)) -ceq "3@1,5@2") "bounded at record 5, the one after it is left out"
Check ((Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief" -UpTo 4)) -ceq "3@1" -and (Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief" -UpTo 2)) -ceq "") "a bound between two messages, or before the first, is honoured exactly"
Check ((Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief" -After 3 -UpTo 6)) -ceq "5@2,6@1" -and (Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief" -After 3 -UpTo 5)) -ceq "5@2") "named from both ends, it is the messages after the first record and up to the second"
Check ((Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "founder")) -ceq "4@1") "for the other reader it is the other speaker's words"
$st = Get-Fold ($said + @((New-Read 7 5)))
Check ((Get-ForSequences @(Get-HordeDecisionMessagesFor -State $st -Reader "warchief")) -ceq "6@1") "with no start named it begins from the reader's own mark"

Write-Host ""
Write-Host "--- who may speak, by what route, and who may record whose words ---" -ForegroundColor Cyan
function Get-Saying { param([string]$Speaker = "founder", [string]$Route = "chat-recorded", [string]$Actor = "warchief", [string]$Text = "Yes, do it.") $found = @(); try { $found = @(Test-HordeDecisionSaying -Speaker $Speaker -Route $Route -Actor $Actor -Text $Text) } catch { $found = @("THREW: " + $_.Exception.Message) }; return ,$found }
Check ((Get-Saying).Count -eq 0 -and (Get-Saying -Speaker "warchief" -Route "command").Count -eq 0 -and (Get-Saying -Route "window" -Actor "founder").Count -eq 0) "CONTROL: the founder's chat words recorded by the warchief, the warchief's own reply, and the founder typing in the window may each be written"
Check (Test-Says (Get-Saying -Speaker "orc") "'speaker' is 'orc', which is not someone who speaks") "a speaker outside the list is refused, with the list"
Check (Test-Says (Get-Saying -Route "telepathy") "'route' is 'telepathy', which is not a way words arrive") "a route outside the list is refused, with the list"
Check (Test-Says (Get-Saying -Speaker "warchief" -Route "chat-recorded") "recorded by the warchief from chat are never the warchief's") "the warchief cannot record its own words as the founder's chat: that route carries the founder's words only"
Check (Test-Says (Get-Saying -Speaker "founder" -Route "command") "by command are never the founder's") "the founder's words do not arrive by command"
Check (Test-Says (Get-Saying -Speaker "warchief" -Route "window" -Actor "founder") "typed in the window are never the warchief's") "nor the warchief's through the window"
Check (Test-Says (Get-Saying -Route "window" -Actor "warchief") "typed in the window are recorded only by: founder") "words typed in the window are recorded by the founder's own window, never by the warchief in his name"
Check (Test-Says (Get-Saying -Route "chat-recorded" -Actor "founder") "recorded by the warchief from chat are recorded only by: warchief") "and words from chat are recorded by the warchief, which is what the route says"
Check (Test-Says (Get-Saying -Text "") "'text' is blank") "saying nothing is refused"
Check (Test-Says (Get-Saying -Text "  `r`n `t ") "'text' is blank") "and so are words that are only spaces and line breaks"
$hundredThousand = ("word " * 20000)
Check ($hundredThousand.Length -eq 100000 -and (Get-Saying -Text $hundredThousand).Count -eq 0) "100,000 characters may be said"
Check ((Get-Saying -Text ("x" * 500000)).Count -eq 0) "and so may 500,000, the most a text may be"
$tooLong = Get-Saying -Text ("x" * 500001)
Check ((Test-Says $tooLong "'text' is 500001 characters long; the most is 500000") -and (Test-Says $tooLong "refused whole, never cut") -and @($tooLong | Where-Object { "$_".Length -gt 300 }).Count -eq 0) "one character more is refused whole, with the count, and the finding does not hold the text"
# Right-to-left text as it really arrives: the direction marks, and the embedding and isolate
# characters a phone's keyboard and a chat program put around it. A question's field refuses those;
# words said are kept exactly.
$hebrewSaid = "" + [char]0x202B + [char]0x05DB + [char]0x05DF + [char]0x200F + ", " + [char]0x2067 + [char]0x05EA + [char]0x05DE + [char]0x05E9 + [char]0x05D9 + [char]0x05DA + [char]0x2069 + [char]0x202C + " " + [char]0x200E + "(yes)" + [char]0x200D + [char]0x2028 + "next"
Check ((Get-Saying -Text $hebrewSaid).Count -eq 0) "Hebrew with direction marks, an embedding, an isolate and a line separator may be said as it is"
Check (@(Test-HordeDecisionNote -Text $hebrewSaid -Name "outcome").Count -gt 0) "CONTROL: the same characters in a question's own text are refused, so this is the rule for words said and not the absence of one"
Check ((Get-Saying -Text ("line one`r`nline two`n`tindented")).Count -eq 0) "line breaks of both kinds and a tab may be said"
foreach ($bad in @(0x1B, 0x00, 0x07, 0x08, 0x7F, 0x85)) {
    $withControl = "before" + [char]$bad + "after"
    $found = Get-Saying -Text $withControl
    Check ((Test-Says $found ("'text' holds the character U+" + $bad.ToString("X4"))) -and (Test-Says $found "refused, not removed") -and -not (Test-Says $found "before")) ("a control character (U+" + $bad.ToString("X4") + ") is refused by its code point, and the words around it are not repeated")
}

Write-Host ""
Write-Host "--- a conversation record of the wrong shape never stops the list ---" -ForegroundColor Cyan
$good = @((New-Added 1 1), (New-Said 2 1 -Text "kept"))
foreach ($case in @(
    @{ what = "a message with no text"; record = (New-Record 3 "message-said" ([ordered]@{ number = 1; speaker = "founder"; route = "window"; wordingVersion = 1 })); says = "is not what a message-said record holds" }
    @{ what = "a message whose text is not text"; record = (New-Record 3 "message-said" ([ordered]@{ number = 1; speaker = "founder"; route = "window"; text = 5; wordingVersion = 1 })); says = "is not what a message-said record holds" }
    @{ what = "a message with a member no message has"; record = (New-Record 3 "message-said" ([ordered]@{ number = 1; speaker = "founder"; route = "window"; text = "x"; wordingVersion = 1; turn = "founder" })); says = "is not what a message-said record holds" }
    @{ what = "a message whose speaker is not a label"; record = (New-Said 3 1 -Speaker "The Founder"); says = "is not what a message-said record holds" }
    @{ what = "a message said to wording 0"; record = (New-Said 3 1 -Wording 0); says = "is not what a message-said record holds" }
    @{ what = "a message said to wording 1e30"; record = (New-Said 3 1 -Wording 1e30); says = "'wordingVersion' is beyond 999999999" }
    @{ what = "a read mark with no reader"; record = (New-Record 3 "messages-read" ([ordered]@{ upTo = 2 })); says = "is not what a messages-read record holds" }
    @{ what = "a read mark up to record 1e30"; record = (New-Read 3 1e30); says = "'upTo' is beyond 9999999999" }
    @{ what = "a read mark up to record 0"; record = (New-Read 3 0); says = "is not what a messages-read record holds" }
)) {
    $st = Get-Fold ($good + @($case.record) + @((New-Said 4 1 -Text "and after")))
    Check ($st.unreadable.Count -eq 1 -and $st.unreadable[0].sequence -eq 3 -and $st.unreadable[0].reason -like ("*" + $case.says + "*") -and (Get-Texts (Get-Thread $st 1)) -ceq "kept | and after") ($case.what + " is unreadable by name, and the messages before and after it are still in the thread" + $(if ($st.unreadable.Count -eq 1) { "" } else { " (unreadable: " + $st.unreadable.Count + ")" }))
}
$st = Get-Fold ($good + @((New-Said 3 99 -Text "to no question"), (New-Read 4 2)))
Check ($st.ignored.Count -eq 1 -and $st.ignored[0].reason -like "*there is no question 99*" -and (Get-Unread (Get-Thread $st 1)) -eq 0 -and $st.ids.Count -eq 4) "a message to a question that does not exist is reported and changes nothing, and a read mark after it still applies: it needs no question number"
Check ($st.ids[([long]4).ToString("x32")].number -eq 0 -and $st.ids[([long]2).ToString("x32")].number -eq 1) "the list knows a message's record by the question it is under, and a read mark's as being about no one question"

Write-Host ""
Write-Host "--- a question as shown ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Said 2 1 -Text "said"), (New-Record 3 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })))
$view = ConvertTo-HordeDecisionView -Question $st.questions[1] -State $st -Messages
$summary = ConvertTo-HordeDecisionView -Question $st.questions[1] -State $st
Check ($view.thread.count -eq 1 -and @($view.thread.messages).Count -eq 1 -and $summary.thread.count -eq 1 -and $null -eq $summary.thread.PSObject.Properties["messages"]) "one question shown carries its messages; in a list it carries their count, whose turn it is and what is unread, and not the messages"
$found = @(Test-HordeSchema -Value $summary -Schema $defs.resultSchema.definitions.view -Root $defs.resultSchema)
Check ($found.Count -eq 0) ("the list's form of a question matches decision-result.v1's view too" + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
$found = @(Test-HordeSchema -Value $view -Schema $defs.resultSchema.definitions.view -Root $defs.resultSchema)
Check ($found.Count -eq 0) ("a question of the list, as plain data, matches decision-result.v1's view" + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
$view.title = "changed by the caller"
Check ($st.questions[1].title -clike "Is question number 1*") "and it is a copy: changing it does not reach the list"

Complete-HordeSuite -Success "a question's number is permanent, an unreadable record is reported and renumbers nothing, and what must not be written is refused by name"
