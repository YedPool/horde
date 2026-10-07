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
Check (($kindNames -join ",") -ceq "question-added,question-updated,question-closed,question-reopened") "the event kinds of this slice are the four of the design"
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

Write-Host ""
Write-Host "--- one id, one record to answer from ---" -ForegroundColor Cyan
$sameId = "ab" * 16
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." }) -Id $sameId), (New-Record 3 "question-reopened" ([ordered]@{ number = 1; reason = "again" }) -Id $sameId))
Check ($st.ids[$sameId].sequence -eq 2 -and $st.ids[$sameId].kind -ceq "question-closed") "when two records carry one id, the first is the one a repost is answered from"
Check ($st.ids.Count -eq 2 -and $st.ids[$sameId].number -eq 1 -and $st.ids[$sameId].applied -eq $true) "CONTROL: the list knows each id's record, its question and that it applied"

Write-Host ""
Write-Host "--- a question as shown ---" -ForegroundColor Cyan
$st = Get-Fold @((New-Added 1 1), (New-Record 2 "question-closed" ([ordered]@{ number = 1; outcome = "Done." })))
$view = ConvertTo-HordeDecisionView -Question $st.questions[1]
$found = @(Test-HordeSchema -Value $view -Schema $defs.resultSchema.definitions.view -Root $defs.resultSchema)
Check ($found.Count -eq 0) ("a question of the list, as plain data, matches decision-result.v1's view" + $(if ($found.Count) { " (" + ($found -join "; ") + ")" } else { "" }))
$view.title = "changed by the caller"
Check ($st.questions[1].title -clike "Is question number 1*") "and it is a copy: changing it does not reach the list"

Complete-HordeSuite -Success "a question's number is permanent, an unreadable record is reported and renumbers nothing, and what must not be written is refused by name"
