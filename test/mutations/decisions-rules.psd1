# Mutations of decisions/Rules.ps1: what the decisions records mean and what may be written. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-rules.psd1
# Each switches off or loosens one rule; test\test-decisions-rules.ps1 must fail for every one.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-rules.ps1"
    Mutations = @(
        # --- who may write is the rules' list ---
        @{ Name = "another-actor-may-write"
           Find = '$script:HordeDecisionActors = @("warchief")'
           Replace = '$script:HordeDecisionActors = @("warchief", "goblin")' }
        # --- a secret written as a field's name ---
        @{ Name = "secret-as-a-field-name-not-seen"
           Find = 'if ($nameKind -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "secret-field-name-repeated-to-say-where"
           Find = '$where = "a field whose name is not repeated here"'
           Replace = '$where = "''" + $k + "''"' }
        # --- a number too large to be one is unreadable, never a throw ---
        @{ Name = "huge-question-number-cast"
           Find = 'if ($entry.about -ceq "question" -and -not (Test-HordeDecisionCount -Value $Ev.data.number -Most $script:HordeDecisionMaxNumber)) {'
           Replace = 'if ($false) {' }
        @{ Name = "huge-sequence-number-cast"
           Find = 'if (-not (Test-HordeDecisionCount -Value $Ev.sequence -Most (Get-HordeDecisionMaxSequence))) {'
           Replace = 'if ($false) {' }
        @{ Name = "ten-digit-question-number-believed"
           Find = '$script:HordeDecisionMaxNumber = 999999999'
           Replace = '$script:HordeDecisionMaxNumber = 9999999999' }
        @{ Name = "largest-question-number-refused"
           Find = 'return ($size -ge 1 -and $size -le $Most)'
           Replace = 'return ($size -ge 1 -and $size -lt $Most)' }
        # --- the number is permanent ---
        @{ Name = "given-number-given-again"
           Find = 'if ($number -le [int]$State.lastNumber) {'
           Replace = 'if ($false) {' }
        @{ Name = "contradicting-record-not-counted"
           Find = '        $State.pending = [int]$State.pending + 1'
           Replace = '        $State.pending = [int]$State.pending' }
        @{ Name = "unreadable-record-leaves-no-number-unused"
           Find = 'return ([int]$State.lastNumber + [int]$State.pending + 1)'
           Replace = 'return ([int]$State.lastNumber + 1)' }
        @{ Name = "unreadable-record-not-counted"
           Find = '$State.pending = [int]$span + [int]$State.pending'
           Replace = '$State.pending = [int]$State.pending' }
        @{ Name = "gap-of-several-records-costs-one-number"
           Find = '$State.pending = [int]$span + [int]$State.pending'
           Replace = '$State.pending = 1 + [int]$State.pending' }
        @{ Name = "order-ends-where-a-gap-starts"
           Find = '$State.lastSequence = [long]$Record.sequence + $span - 1'
           Replace = '$State.lastSequence = [long]$Record.sequence' }
        @{ Name = "pending-kept-after-a-readable-add"
           Find = '    $State.pending = 0'
           Replace = '    $State.pending = [int]$State.pending' }
        @{ Name = "number-counted-not-read"
           Find = '    $number = [int]$Ev.data.number'
           Replace = '    $number = $State.questions.Count + 1' }
        @{ Name = "unreadable-number-reads-as-absent"
           Find = 'if ($Number -ge 1 -and $Number -le ([int]$State.lastNumber + [int]$State.pending)) { return "unreadable" }'
           Replace = '' }
        # --- what a record may do to a question ---
        @{ Name = "closed-question-changed"
           Find = 'if ($question.state -cne "open") { return ("question " + $question.number + " is " + $question.state + ", and only an open question can be changed; reopen it first") }'
           Replace = '' }
        @{ Name = "closed-question-closed-again"
           Find = 'if ($question.state -cne "open") { return ("question " + $question.number + " is already " + $question.state) }'
           Replace = '' }
        @{ Name = "open-question-reopened"
           Find = 'if ($question.state -cne "closed") { return ("question " + $question.number + " is " + $question.state + ", and only a closed question can be reopened") }'
           Replace = '' }
        @{ Name = "reopened-question-keeps-its-outcome"
           Find = '    $question.outcome = ""'
           Replace = '' }
        @{ Name = "reopened-question-stays-closed"
           Find = '    $question.state = "open"'
           Replace = '' }
        @{ Name = "empty-change-recorded"
           Find = 'if ($changed.Count -eq 0) { return ("it changes nothing: every field it names already has that value in question " + $question.number) }'
           Replace = '' }
        @{ Name = "same-value-counted-as-a-change"
           Find = 'if ((ConvertTo-HordeDecisionCanonicalText -Value $question[$name]) -ceq (ConvertTo-HordeDecisionCanonicalText -Value $changes[$name])) { continue }'
           Replace = '' }
        @{ Name = "wording-never-counted"
           Find = 'if ($script:HordeDecisionFields[$name].wording) { $reworded = $true }'
           Replace = '' }
        @{ Name = "every-change-is-a-new-wording"
           Find = 'if ($script:HordeDecisionFields[$name].wording) { $reworded = $true }'
           Replace = '$reworded = $true' }
        @{ Name = "options-not-wording"
           Find = 'options        = @{ type = "list"; oneLine = $true;  wording = $true }'
           Replace = 'options        = @{ type = "list"; oneLine = $true;  wording = $false }' }
        @{ Name = "record-about-an-unreadable-question-says-none"
           Find = 'if ((Get-HordeDecisionNumberStatus -State $State -Number $about) -eq "unreadable") {'
           Replace = 'if ($false) {' }
        # --- a stored record's shape ---
        @{ Name = "envelope-not-checked"
           Find = 'if ($found.Count -gt 0) { return @("it is not a decision-event.v1 record: " + (@($found | Select-Object -First 3) -join "; ")) }'
           Replace = '' }
        @{ Name = "kind-data-not-checked"
           Find = '$found = @(Test-HordeSchema -Value $Ev.data -Schema $dataSchema -Path ''$.data'' -Root $Definitions.eventSchema)'
           Replace = '$found = @()' }
        @{ Name = "words-inside-a-record-not-checked"
           Find = 'if ($found.Count -eq 0 -and $entry.words -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "record-in-the-wrong-place-believed"
           Find = 'elseif ([long]$Record.data.sequence -ne [long]$Record.sequence) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "damaged-record-read-as-data"
           Find = 'if ($Record.kind -cne "ok") { $why = "$($Record.reason)" }'
           Replace = 'if ($false) { $why = "$($Record.reason)" }' }
        @{ Name = "long-reason-kept-whole"
           Find = 'if ($why.Length -gt 400) {'
           Replace = 'if ($false) {' }
        @{ Name = "record-that-did-not-apply-not-reported"
           Find = 'if ("$applied" -ne "") { [void]$State.ignored.Add('
           Replace = 'if ($false) { [void]$State.ignored.Add(' }
        @{ Name = "later-record-takes-the-id"
           Find = 'if (-not $State.ids.ContainsKey("$($Ev.id)")) {'
           Replace = 'if ($true) {' }
        # --- a title explains itself ---
        @{ Name = "title-without-letters-not-named"
           Find = 'if ($Title -notmatch ''\p{L}'') {'
           Replace = 'if ($false) {' }
        @{ Name = "reference-only-title-not-named"
           Find = 'if ($words -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "short-title-allowed"
           Find = 'if ($words -lt $script:HordeDecisionMinTitleWords) {'
           Replace = 'if ($false) {' }
        @{ Name = "reference-words-count-as-explaining"
           Find = '$rest = [regex]::Replace($rest, ''(?i)\b(pull[\s-]*requests?|prs?|merge[\s-]*requests?|mrs?|issues?|tickets?|bugs?)(?!\p{L})'', '' '')'
           Replace = '$rest = $rest' }
        @{ Name = "link-counts-as-explaining"
           Find = '$rest = [regex]::Replace($Title, ''(?i)\b[a-z][a-z0-9+.-]*://\S+'', '' '')'
           Replace = '$rest = $Title' }
        @{ Name = "reference-joined-to-its-number-counts-as-a-word"
           Find = 'tickets?|bugs?)(?!\p{L})'', '' '')'
           Replace = 'tickets?|bugs?)\b'', '' '')' }
        @{ Name = "sentence-without-spaces-counted-as-one-word"
           Find = '$words = [regex]::Matches($rest, ($script:HordeDecisionUnspacedLetter + ''|\p{L}[\p{L}\p{M}]*'')).Count'
           Replace = '$words = [regex]::Matches($rest, ''\p{L}[\p{L}\p{M}]*'').Count' }
        @{ Name = "two-word-title-allowed"
           Find = '$script:HordeDecisionMinTitleWords = 3'
           Replace = '$script:HordeDecisionMinTitleWords = 2' }
        @{ Name = "title-rule-not-applied"
           Find = 'if ($title.Trim() -ne "") { $why = Get-HordeDecisionTitleProblem -Title $title; if ($why -ne "") { [void]$out.Add($why) } }'
           Replace = '' }
        # --- what a question must hold ---
        @{ Name = "unexplained-question-allowed"
           Find = '-and "$(Get-HordeDecisionMember -Object $Question -Name ''yesMeans'')".Trim() -eq "") {'
           Replace = '-and $false) {' }
        @{ Name = "required-fields-not-checked"
           Find = 'foreach ($name in $script:HordeDecisionRequiredFields) {'
           Replace = 'foreach ($name in @()) {' }
        @{ Name = "group-not-required"
           Find = '$script:HordeDecisionRequiredFields = @("title", "kind", "group", "askedBy")'
           Replace = '$script:HordeDecisionRequiredFields = @("title", "kind", "askedBy")' }
        @{ Name = "unknown-kind-allowed"
           Find = 'if (-not (Test-HordeDecisionMember -Object $Kinds -Name $kind)) {'
           Replace = 'if ($false) {' }
        @{ Name = "one-option-is-a-choice"
           Find = 'if ($items.Count -lt 2) {'
           Replace = 'if ($items.Count -lt 1) {' }
        @{ Name = "repeated-option-allowed"
           Find = 'if ($distinct.Count -ne $items.Count) {'
           Replace = 'if ($false) {' }
        @{ Name = "list-of-another-kind-stored"
           Find = 'elseif ($items.Count -gt 0) { [void]$out.Add("''" + $listName'
           Replace = 'elseif ($false) { [void]$out.Add("''" + $listName' }
        @{ Name = "blank-item-allowed"
           Find = 'if ("$text".Trim() -eq "") { [void]$out.Add($where + " is blank") }'
           Replace = '' }
        @{ Name = "line-break-in-a-one-line-field"
           Find = 'if ("$text" -match "[\r\n]") {'
           Replace = 'if ($false) {' }
        @{ Name = "title-may-have-lines"
           Find = 'title          = @{ type = "text"; oneLine = $true;  wording = $true }'
           Replace = 'title          = @{ type = "text"; oneLine = $false; wording = $true }' }
        @{ Name = "long-text-not-refused"
           Find = 'if ("$text".Length -gt $most) {'
           Replace = 'if ($false) {' }
        @{ Name = "long-text-limit-lower-than-required"
           Find = '$script:HordeDecisionMaxTextChars = 500000'
           Replace = '$script:HordeDecisionMaxTextChars = 99999' }
        @{ Name = "long-list-allowed"
           Find = 'if ($spec.type -eq "list" -and $texts.Count -gt $script:HordeDecisionMaxListItems) {'
           Replace = 'if ($false) {' }
        # --- characters that are not text ---
        @{ Name = "character-that-is-not-text-stored-in-a-question"
           Find = 'if ($notText -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "character-that-is-not-text-stored-in-a-note"
           Find = 'if ($unfit -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "format-characters-allowed"
           Find = '$script:HordeDecisionNotTextClasses = ''\p{Cc}\p{Cf}\p{Zl}\p{Zp}'''
           Replace = '$script:HordeDecisionNotTextClasses = ''\p{Cc}\p{Zl}\p{Zp}''' }
        @{ Name = "line-and-paragraph-separators-allowed"
           Find = '$script:HordeDecisionNotTextClasses = ''\p{Cc}\p{Cf}\p{Zl}\p{Zp}'''
           Replace = '$script:HordeDecisionNotTextClasses = ''\p{Cc}\p{Cf}''' }
        @{ Name = "control-characters-allowed"
           Find = '$script:HordeDecisionNotTextClasses = ''\p{Cc}\p{Cf}\p{Zl}\p{Zp}'''
           Replace = '$script:HordeDecisionNotTextClasses = ''\p{Cf}\p{Zl}\p{Zp}''' }
        @{ Name = "direction-marks-and-joiners-refused-in-a-question-field"
           Find = '$script:HordeDecisionQuestionFieldKeeps = ''\r\n\u200C-\u200F'''
           Replace = '$script:HordeDecisionQuestionFieldKeeps = ''\r\n''' }
        @{ Name = "question-field-takes-what-a-message-takes"
           Find = '$script:HordeDecisionQuestionFieldKeeps = ''\r\n\u200C-\u200F'''
           Replace = '$script:HordeDecisionQuestionFieldKeeps = ''\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C''' }
        @{ Name = "embeddings-and-overrides-refused-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u2060\u2066-\u2069\u061C''' }
        @{ Name = "isolates-refused-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u061C''' }
        @{ Name = "zero-width-space-refused-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200C-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C''' }
        @{ Name = "word-joiner-refused-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2066-\u2069\u061C''' }
        @{ Name = "byte-order-mark-taken-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C\uFEFF''' }
        @{ Name = "line-separator-taken-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C\u2028''' }
        @{ Name = "tab-refused-in-a-message"
           Find = '$script:HordeDecisionSpokenMessageKeeps = ''\t\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C'''
           Replace = '$script:HordeDecisionSpokenMessageKeeps = ''\r\n\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\u061C''' }
        @{ Name = "tab-allowed-in-one-line"
           Find = '$script:HordeDecisionNotTextInOneLine = ''['' + $script:HordeDecisionNotTextClasses + ''-['' + $script:HordeDecisionQuestionFieldKeeps + '']]'''
           Replace = '$script:HordeDecisionNotTextInOneLine = ''['' + $script:HordeDecisionNotTextClasses + ''-[\t'' + $script:HordeDecisionQuestionFieldKeeps + '']]''' }
        @{ Name = "tab-refused-in-several-lines"
           Find = '$script:HordeDecisionNotTextInLines = ''['' + $script:HordeDecisionNotTextClasses + ''-[\t'' + $script:HordeDecisionQuestionFieldKeeps + '']]'''
           Replace = '$script:HordeDecisionNotTextInLines = ''['' + $script:HordeDecisionNotTextClasses + ''-['' + $script:HordeDecisionQuestionFieldKeeps + '']]''' }
        @{ Name = "message-never-says-it-holds-direction-characters"
           Find = '        holdsDirectionOrInvisibleCharacters = [bool]([regex]::IsMatch([string]$Message.text, $script:HordeDecisionDirectionOrInvisible))'
           Replace = '        holdsDirectionOrInvisibleCharacters = $false' }
        @{ Name = "every-message-says-it-holds-direction-characters"
           Find = '        holdsDirectionOrInvisibleCharacters = [bool]([regex]::IsMatch([string]$Message.text, $script:HordeDecisionDirectionOrInvisible))'
           Replace = '        holdsDirectionOrInvisibleCharacters = $true' }
        @{ Name = "one-line-field-held-to-the-rule-for-several-lines"
           Find = '$notText = Get-HordeDecisionCharProblem -Text "$text" -OneLine:([bool]$spec.oneLine)'
           Replace = '$notText = Get-HordeDecisionCharProblem -Text "$text"' }
        @{ Name = "blank-note-allowed"
           Find = 'if ($Text.Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "note-of-several-lines-allowed"
           Find = 'if ($Text -match "[\r\n]") {'
           Replace = 'if ($false) {' }
        # --- no secrets, and no echo: the patterns are core/Secrets.ps1's (test\mutations\secrets-decisions.psd1) ---
        @{ Name = "secret-repeated-in-the-finding"
           Find = '[void]$out.Add($Path + " holds what looks like " + $kind + ". A secret'
           Replace = '[void]$out.Add($Path + " holds " + $Value + ", which looks like " + $kind + ". A secret' }
        @{ Name = "secret-in-a-list-not-seen"
           Find = 'elseif ($Value -is [System.Collections.IList]) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "secret-in-a-member-not-seen"
           Find = 'elseif ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {'
           Replace = 'elseif ($false) {' }
        # --- a request's hash ---
        @{ Name = "hash-follows-key-order"
           Find = '[Array]::Sort($sorted, [System.StringComparer]::Ordinal)'
           Replace = '' }
        @{ Name = "quote-and-escaped-quote-hash-alike"
           Find = 'return (''"'' + $Value.Replace(''\'', ''\\'').Replace(''"'', ''\"'') + ''"'')'
           Replace = 'return (''"'' + $Value.Replace(''\'', '''') + ''"'')' }
        @{ Name = "non-json-value-hashed"
           Find = 'throw ("a value of type " + $Value.GetType().FullName + " cannot be hashed: only JSON data can")'
           Replace = 'return "x"' }
        # --- a question as shown ---
        @{ Name = "view-shares-the-list"
           Find = 'return [pscustomobject]$view'
           Replace = 'return $Question' }
        # --- the compatibility contract: a record of a later kind is set aside, never a possible question ---
        @{ Name = "later-kind-read-as-damage"
           Find = 'elseif ($null -eq $script:HordeDecisionEventKinds["$($Record.data.kind)"]) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "later-kind-costs-a-question-number"
           Find = '            $later = "$($Record.data.kind)"'
           Replace = '            $later = "$($Record.data.kind)"; $State.pending = [int]$State.pending + 1' }
        @{ Name = "later-kind-reported-once-a-record"
           Find = 'if ($State.notUnderstood.Contains($later)) { $seen ='
           Replace = 'if ($false) { $seen =' }
        @{ Name = "later-kind-range-ends-at-its-first-record"
           Find = '$seen.count = [int]$seen.count + 1; $seen.last = [long]$Record.sequence }'
           Replace = '$seen.count = [int]$seen.count + 1 }' }
        @{ Name = "id-of-a-later-kind-not-seen"
           Find = 'if (-not $State.ids.ContainsKey("$($Record.data.id)")) {'
           Replace = 'if ($false) {' }
        @{ Name = "later-kind-in-another-envelope-set-aside"
           Find = 'if ($cover.Count -gt 0) { $why = $cover[0] }'
           Replace = 'if ($false) { $why = $cover[0] }' }
        @{ Name = "later-kind-out-of-its-place-set-aside"
           Find = 'elseif ([long]$Record.data.sequence -ne [long]$Record.sequence) { $why ='
           Replace = 'elseif ($false) { $why =' }
        @{ Name = "known-kind-with-bad-data-not-checked"
           Find = '            if ($shape.Count -gt 0) { $why = $shape[0] }'
           Replace = '' }
        # --- a set-aside record's number still raises the floor ---
        @{ Name = "later-kind-number-does-not-raise-the-floor"
           Find = '$State.lastNumber = [int]$carried; '
           Replace = '' }
        @{ Name = "later-kind-number-lowers-the-floor"
           Find = '-and [double]$carried -gt ([double]$State.lastNumber + [double]$State.pending)) {'
           Replace = ') {' }
        @{ Name = "anything-in-a-number-field-taken-as-a-question-number"
           Find = 'if ((Test-HordeDecisionCount -Value $carried -Most $script:HordeDecisionMaxNumber) -and'
           Replace = 'if (($null -ne $carried) -and' }
        @{ Name = "unreadable-count-kept-past-a-raised-floor"
           Find = '; $State.pending = 0'
           Replace = '' }
        # --- the conversation under a question: kept, in order, and changing nothing ---
        @{ Name = "words-under-a-closed-question-dropped"
           Find = '    if ($stated) { $seen = [int]$Ev.data.wordingVersion }'
           Replace = '    if ($question.state -cne "open") { return "the question is closed" }; if ($stated) { $seen = [int]$Ev.data.wordingVersion }' }
        @{ Name = "words-under-a-closed-question-reopen-it"
           Find = '        arrivedAfterClosing = [bool]($question.state -cne "open")'
           Replace = '        arrivedAfterClosing = [bool]($question.state -cne "open"); reopened = [bool]($question.state = "open")' }
        @{ Name = "arrival-after-closing-not-flagged"
           Find = '        arrivedAfterClosing = [bool]($question.state -cne "open")'
           Replace = '        arrivedAfterClosing = $false' }
        @{ Name = "words-to-an-earlier-wording-dropped"
           Find = 'if ($stated -and $seen -gt [int]$question.wordingVersion) {'
           Replace = 'if ($stated -and $seen -ne [int]$question.wordingVersion) {' }
        @{ Name = "wording-not-yet-written-believed"
           Find = 'if ($stated -and $seen -gt [int]$question.wordingVersion) {'
           Replace = 'if ($false) {' }
        @{ Name = "earlier-wording-not-flagged"
           Find = '        saidToEarlierWording = [bool]($stated -and $seen -lt [int]$question.wordingVersion)'
           Replace = '        saidToEarlierWording = $false' }
        @{ Name = "wording-of-the-moment-flagged-as-earlier"
           Find = '        saidToEarlierWording = [bool]($stated -and $seen -lt [int]$question.wordingVersion)'
           Replace = '        saidToEarlierWording = [bool]($stated -and $seen -le [int]$question.wordingVersion)' }
        @{ Name = "unstated-wording-flagged-as-earlier"
           Find = '        saidToEarlierWording = [bool]($stated -and $seen -lt [int]$question.wordingVersion)'
           Replace = '        saidToEarlierWording = [bool]($seen -lt [int]$question.wordingVersion)' }
        @{ Name = "unstated-wording-said-to-be-stated"
           Find = '        wordingStated = [bool]$stated'
           Replace = '        wordingStated = $true' }
        @{ Name = "record-without-a-wording-unreadable"
           Find = 'if (-not (Test-HordeDecisionMember -Object $Ev.data -Name $member)) { continue }'
           Replace = '' }
        @{ Name = "window-need-not-state-its-wording"
           Find = 'if ([bool]$routeEntry.statesWording -and -not $WordingStated) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "chat-must-state-a-wording-nobody-knows"
           Find = '    "chat-recorded" = @{ speakers = @("founder");  actors = @("warchief"); shown = "recorded by the warchief from chat"; statesWording = $false }'
           Replace = '    "chat-recorded" = @{ speakers = @("founder");  actors = @("warchief"); shown = "recorded by the warchief from chat"; statesWording = $true }' }
        @{ Name = "earlier-wording-judged-against-todays-wording"
           Find = 'saidToEarlierWording = [bool]$Message.saidToEarlierWording'
           Replace = 'saidToEarlierWording = [bool]([int]$Message.wordingVersion -lt [int](@($State.questions.Values | Where-Object { $_.thread -contains $Message })[0].wordingVersion))' }
        @{ Name = "words-trimmed"
           Find = '        text = [string]$Ev.data.text'
           Replace = '        text = ([string]$Ev.data.text).Trim()' }
        @{ Name = "speaking-counts-as-a-change-to-the-question"
           Find = '    $speaker = "$($Ev.data.speaker)"'
           Replace = '    $speaker = "$($Ev.data.speaker)"; Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "said"' }
        @{ Name = "thread-in-reverse-order"
           Find = '    $views = @($Question.thread | ForEach-Object { ConvertTo-HordeDecisionMessageView -Message $_ -State $State })'
           Replace = '    $views = @($Question.thread | Sort-Object { -[long]$_.sequence } | ForEach-Object { ConvertTo-HordeDecisionMessageView -Message $_ -State $State })' }
        @{ Name = "list-form-carries-the-messages"
           Find = '    if ($Messages) { $thread["messages"] = $views }'
           Replace = '    $thread["messages"] = $views' }
        # --- whose turn it is ---
        @{ Name = "turn-does-not-pass-when-someone-speaks"
           Find = 'if ($question.state -ceq "open" -and $script:HordeDecisionSpeakers.Contains($speaker) -and $last.asks -and $last.act -eq "") { $question.turn = "$($script:HordeDecisionSpeakers[$speaker].then)" }'
           Replace = '' }
        @{ Name = "turn-passes-under-a-closed-question"
           Find = 'if ($question.state -ceq "open" -and $script:HordeDecisionSpeakers.Contains($speaker) -and $last.asks -and $last.act -eq "") { $question.turn = "$($script:HordeDecisionSpeakers[$speaker].then)" }'
           Replace = 'if ($script:HordeDecisionSpeakers.Contains($speaker) -and $last.asks -and $last.act -eq "") { $question.turn = "$($script:HordeDecisionSpeakers[$speaker].then)" }' }
        @{ Name = "turn-stays-with-the-speaker"
           Find = '    founder  = @{ shown = "the founder";  then = "warchief"; reads = $false }'
           Replace = '    founder  = @{ shown = "the founder";  then = "founder"; reads = $false }' }
        @{ Name = "closing-leaves-the-turn"
           Find = '    $question.turn = $script:HordeDecisionNoTurn'
           Replace = '' }
        @{ Name = "reopening-leaves-nobodys-turn"
           Find = '    $question.turn = $script:HordeDecisionFirstTurn'
           Replace = '' }
        @{ Name = "first-turn-is-the-warchiefs"
           Find = '$script:HordeDecisionFirstTurn = "founder"'
           Replace = '$script:HordeDecisionFirstTurn = "warchief"' }
        @{ Name = "nobodys-turn-shown-as-a-speaker"
           Find = '    if ($turn -cne $script:HordeDecisionNoTurn) { $turnShown = Get-HordeDecisionSpeakerShown -Speaker $turn }'
           Replace = '    $turnShown = "the " + $turn' }
        # --- what is unread, from the read mark ---
        @{ Name = "own-words-unread-by-their-speaker"
           Find = 'if ($reader -cne $Message.speaker -and [long]$Message.sequence -gt (Get-HordeDecisionReadMark -State $State -Reader $reader)) { $unreadBy.Add($reader) }'
           Replace = 'if ([long]$Message.sequence -gt (Get-HordeDecisionReadMark -State $State -Reader $reader)) { $unreadBy.Add($reader) }' }
        @{ Name = "message-at-the-mark-unread"
           Find = 'if ($reader -cne $Message.speaker -and [long]$Message.sequence -gt (Get-HordeDecisionReadMark -State $State -Reader $reader)) { $unreadBy.Add($reader) }'
           Replace = 'if ($reader -cne $Message.speaker -and [long]$Message.sequence -ge (Get-HordeDecisionReadMark -State $State -Reader $reader)) { $unreadBy.Add($reader) }' }
        @{ Name = "read-mark-goes-back"
           Find = 'if ($upTo -le $had) { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "same-mark-again-is-a-new-marking"
           Find = 'if ($upTo -le $had) { return ('
           Replace = 'if ($upTo -lt $had) { return (' }
        @{ Name = "mark-of-the-future-believed"
           Find = 'if ($upTo -ge [long]$Ev.sequence) { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "mark-up-to-the-record-before-refused"
           Find = 'if ($upTo -ge [long]$Ev.sequence) { return ('
           Replace = 'if ($upTo -ge ([long]$Ev.sequence - 1)) { return (' }
        @{ Name = "one-readers-mark-is-everyones"
           Find = '    $State.readMarks[$reader] = $upTo'
           Replace = '    foreach ($everyone in @($script:HordeDecisionSpeakers.Keys)) { $State.readMarks[$everyone] = $upTo }' }
        @{ Name = "marking-not-remembered-for-a-repost"
           Find = '    $State.readEvents[[long]$Ev.sequence] = [pscustomobject]@{ reader = $reader; from = $had; upTo = $upTo }'
           Replace = '' }
        @{ Name = "founder-given-an-inbox-unasked"
           Find = '    founder  = @{ shown = "the founder";  then = "warchief"; reads = $false }'
           Replace = '    founder  = @{ shown = "the founder";  then = "warchief"; reads = $true }' }
        # --- what a reader is to read ---
        @{ Name = "inbox-holds-the-readers-own-words"
           Find = '            if ($message.speaker -ceq $Reader) { continue }'
           Replace = '' }
        @{ Name = "inbox-bound-left-out"
           Find = 'if ([long]$message.sequence -le $After -or [long]$message.sequence -gt $UpTo) { continue }'
           Replace = 'if ([long]$message.sequence -le $After) { continue }' }
        @{ Name = "inbox-bound-one-short"
           Find = 'if ([long]$message.sequence -le $After -or [long]$message.sequence -gt $UpTo) { continue }'
           Replace = 'if ([long]$message.sequence -le $After -or [long]$message.sequence -ge $UpTo) { continue }' }
        @{ Name = "inbox-holds-what-was-read"
           Find = 'if ([long]$message.sequence -le $After -or [long]$message.sequence -gt $UpTo) { continue }'
           Replace = 'if ([long]$message.sequence -gt $UpTo) { continue }' }
        @{ Name = "inbox-does-not-start-from-the-mark"
           Find = '    if ($After -lt 0) { $After = Get-HordeDecisionReadMark -State $State -Reader $Reader }'
           Replace = '    if ($After -lt 0) { $After = 0 }' }
        @{ Name = "inbox-question-by-question"
           Find = '    return @($found | Sort-Object { [long]$_.message.sequence })'
           Replace = '    return @($found)' }
        # --- who may speak, by what route, and who may record whose words ---
        @{ Name = "any-speaker"
           Find = 'if (-not $speakerKnown) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "any-route"
           Find = 'if ($null -eq $routeEntry) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "any-speaker-by-any-route"
           Find = 'if (@($routeEntry.speakers) -cnotcontains $Speaker) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "anyone-records-by-any-route"
           Find = 'if (@($routeEntry.actors) -cnotcontains $Actor) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "warchief-may-record-chat-as-its-own-typing"
           Find = '    "window"        = @{ speakers = @("founder");  actors = @("founder");  shown = "typed in the window";                statesWording = $true }'
           Replace = '    "window"        = @{ speakers = @("founder");  actors = @("founder", "warchief");  shown = "typed in the window";                statesWording = $true }' }
        @{ Name = "chat-words-shown-as-typed"
           Find = '    "chat-recorded" = @{ speakers = @("founder");  actors = @("warchief"); shown = "recorded by the warchief from chat"; statesWording = $false }'
           Replace = '    "chat-recorded" = @{ speakers = @("founder");  actors = @("warchief"); shown = "typed in the window"; statesWording = $false }' }
        @{ Name = "blank-words-stored"
           Find = 'if ($Text.Trim().Length -eq 0) { [void]$out.Add("''text'' is blank: nothing was said") }'
           Replace = '' }
        @{ Name = "long-words-stored-whatever-their-length"
           Find = 'if ($Text.Length -gt $script:HordeDecisionMaxTextChars) { [void]$out.Add("''text'' is "'
           Replace = 'if ($false) { [void]$out.Add("''text'' is "' }
        @{ Name = "words-at-the-limit-refused"
           Find = 'if ($Text.Length -gt $script:HordeDecisionMaxTextChars) { [void]$out.Add("''text'' is "'
           Replace = 'if ($Text.Length -ge $script:HordeDecisionMaxTextChars) { [void]$out.Add("''text'' is "' }
        @{ Name = "words-held-to-no-characters"
           Find = '    $notWords = Get-HordeDecisionCharProblem -Text $Text -Said'
           Replace = '    $notWords = ""' }
        @{ Name = "words-held-to-a-question-fields-characters"
           Find = '    $notWords = Get-HordeDecisionCharProblem -Text $Text -Said'
           Replace = '    $notWords = Get-HordeDecisionCharProblem -Text $Text' }
        # --- a conversation record of the wrong shape, and what a kind is about ---
        @{ Name = "huge-wording-or-mark-cast"
           Find = 'if (-not (Test-HordeDecisionCount -Value (Get-HordeDecisionMember -Object $Ev.data -Name $member) -Most $most)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "mark-held-to-a-questions-limit"
           Find = 'if ($entry.counts[$member] -ceq "sequence") { $most = (Get-HordeDecisionMaxSequence) }'
           Replace = '' }
        @{ Name = "read-mark-asked-for-a-question-number"
           Find = 'if ($entry.about -ceq "question" -and -not (Test-HordeDecisionCount -Value $Ev.data.number -Most $script:HordeDecisionMaxNumber)) {'
           Replace = 'if (-not (Test-HordeDecisionCount -Value $Ev.data.number -Most $script:HordeDecisionMaxNumber)) {' }
        @{ Name = "speakers-may-keep-the-list"
           Find = '    return [pscustomobject]@{ roles = @($script:HordeDecisionActors); may = "change the list" }'
           Replace = '    return [pscustomobject]@{ roles = @($script:HordeDecisionSpeakers.Keys); may = "change the list" }' }
        @{ Name = "only-keepers-may-speak"
           Find = 'if ($null -ne $entry -and "$($entry.actors)" -ceq "speakers") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unlisted-speaker-not-shown"
           Find = '    if ($null -eq $entry) { return $Speaker }'
           Replace = '    if ($null -eq $entry) { return "" }' }
    )
}
