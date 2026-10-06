# Mutations of decisions/Rules.ps1: what the decisions records mean and what may be written. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-rules.psd1
# Each switches off or loosens one rule; test\test-decisions-rules.ps1 must fail for every one.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-rules.ps1"
    Mutations = @(
        # --- a number too large to be one is unreadable, never a throw ---
        @{ Name = "huge-question-number-cast"
           Find = 'if (-not (Test-HordeDecisionCount -Value $Ev.data.number -Most $script:HordeDecisionMaxNumber)) {'
           Replace = 'if ($false) {' }
        @{ Name = "huge-sequence-number-cast"
           Find = 'if (-not (Test-HordeDecisionCount -Value $Ev.sequence -Most $script:HordeDecisionMaxSequence)) {'
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
           Find = '$State.pending = 1 + [int]$State.pending'
           Replace = '$State.pending = [int]$State.pending' }
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
           Find = '$rest = [regex]::Replace($Title, ''(?i)\b(pull[\s-]*requests?|prs?|merge[\s-]*requests?|mrs?|issues?|tickets?|bugs?)\b'', '' '')'
           Replace = '$rest = $Title' }
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
        @{ Name = "blank-note-allowed"
           Find = 'if ($Text.Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "note-of-several-lines-allowed"
           Find = 'if ($Text -match "[\r\n]") {'
           Replace = 'if ($false) {' }
        # --- no secrets, and no echo ---
        @{ Name = "private-key-not-seen"
           Find = '"a private key" = ''-----BEGIN [A-Z0-9 ]*PRIVATE KEY'''
           Replace = '"a private key" = ''never-matches-\A\z.''' }
        @{ Name = "access-token-not-seen"
           Find = '"an access token" = ''(?<![A-Za-z0-9])('
           Replace = '"an access token" = ''never-matches-\A\z.(' }
        @{ Name = "web-token-not-seen"
           Find = '"a signed web token" = ''eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.'''
           Replace = '"a signed web token" = ''never-matches-\A\z.''' }
        @{ Name = "bearer-token-not-seen"
           Find = '"a bearer token" = ''(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}'''
           Replace = '"a bearer token" = ''never-matches-\A\z.''' }
        @{ Name = "name-equals-value-not-seen"
           Find = '"a password or key written as name=value" = ''(?i)\b('
           Replace = '"a password or key written as name=value" = ''never-matches-\A\z.(' }
        @{ Name = "password-after-colon-not-seen"
           Find = '"a password written after a colon" = ''(?i)\b('
           Replace = '"a password written after a colon" = ''never-matches-\A\z.(' }
        @{ Name = "random-string-not-seen"
           Find = '-ge $script:HordeDecisionSecretRunBits) {'
           Replace = '-ge 99) {' }
        @{ Name = "one-case-string-refused"
           Find = 'if ($run -cmatch ''[A-Z]'' -and $run -cmatch ''[a-z]'' -and $run -cmatch ''[0-9]'' -and '
           Replace = 'if (' }
        @{ Name = "path-read-as-one-string"
           Find = '$script:HordeDecisionSecretRunPattern = ''[A-Za-z0-9+=_-]{32,}'''
           Replace = '$script:HordeDecisionSecretRunPattern = ''[A-Za-z0-9+=_\\/.:-]{32,}''' }
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
    )
}
