# Mutations of decisions/Console.ps1's side of the conversation under a question: the verbs answer,
# reply and inbox, and the thread as list and show print it. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-console-threads.psd1
# Each breaks one thing the session at the command line relies on; test\test-decisions-console-threads.ps1
# must fail for every one. It is a spec of its own, beside test\mutations\decisions-console.psd1, because
# that suite starts a process for every command and this one starts none: a mutant here is judged in
# seconds.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\test-decisions-console-threads.ps1"
    Mutations = @(
        # --- who speaks is the verb's ---
        @{ Name = "answer-recorded-as-typed-by-the-founder"
           Find = 'operation = "say"; says = @{ speaker = "founder"; route = "chat-recorded" } }'
           Replace = 'operation = "say"; says = @{ speaker = "founder"; route = "window" } }' }
        @{ Name = "reply-recorded-as-the-founders"
           Find = 'operation = "say"; says = @{ speaker = "warchief"; route = "command" } }'
           Replace = 'operation = "say"; says = @{ speaker = "founder"; route = "chat-recorded" } }' }
        @{ Name = "wording-flag-dropped"
           Find = '            $request["wordingVersion"] = [int]$wording'
           Replace = '' }
        @{ Name = "wording-not-checked"
           Find = 'if ($wording -cnotmatch ''\A[1-9][0-9]{0,8}\z'') { throw ('
           Replace = 'if ($false) { throw (' }
        # --- the words ---
        @{ Name = "words-given-twice-taken"
           Find = 'if ($have.ContainsKey("Text") -eq $have.ContainsKey("File")) { throw ('
           Replace = 'if (-not $have.ContainsKey("Text") -and -not $have.ContainsKey("File")) { throw (' }
        @{ Name = "text-of-two-lines-taken"
           Find = 'if ($words -match "[\r\n]") { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "words-trimmed-on-the-way-in"
           Find = '        $request["text"] = $words'
           Replace = '        $request["text"] = $words.Trim()' }
        @{ Name = "blank-line-of-the-words-not-printed"
           Find = 'foreach ($l in @(([string]$Message.text) -split "\r\n|\r|\n")) { [void]$lines.Add($Indent + "    " + $l) }'
           Replace = 'foreach ($l in @(([string]$Message.text) -split "\r\n|\r|\n" | Where-Object { $_.Trim() -ne "" })) { [void]$lines.Add($Indent + "    " + $l) }' }
        @{ Name = "lines-of-the-words-trimmed-when-printed"
           Find = 'foreach ($l in @(([string]$Message.text) -split "\r\n|\r|\n")) { [void]$lines.Add($Indent + "    " + $l) }'
           Replace = 'foreach ($l in @(([string]$Message.text) -split "\r\n|\r|\n")) { [void]$lines.Add($Indent + "    " + $l.Trim()) }' }
        # --- every line can be read with no other context ---
        @{ Name = "message-does-not-say-how-it-was-recorded"
           Find = '[void]$lines.Add($Indent + $Message.speakerShown + ", " + $Message.routeShown + ", " +'
           Replace = '[void]$lines.Add($Indent + $Message.speakerShown + ", " +' }
        @{ Name = "unstated-wording-shown-as-a-wording"
           Find = '    if ($Message.wordingStated) { $wording = "said to wording " + $Message.wordingVersion }'
           Replace = '    $wording = "said to wording " + $Message.wordingVersion' }
        @{ Name = "stated-wording-not-shown"
           Find = '    if ($Message.wordingStated) { $wording = "said to wording " + $Message.wordingVersion }'
           Replace = '' }
        @{ Name = "arrival-after-closing-not-said"
           Find = 'if ($Message.arrivedAfterClosing) { [void]$lines.Add('
           Replace = 'if ($false) { [void]$lines.Add(' }
        @{ Name = "earlier-wording-not-said"
           Find = '    if ($Message.saidToEarlierWording) {'
           Replace = '    if ($false) {' }
        @{ Name = "answer-does-not-say-the-question-stays-closed"
           Find = 'if ($value.message.arrivedAfterClosing) { [void]$lines.Add('
           Replace = 'if ($false) { [void]$lines.Add(' }
        @{ Name = "answer-does-not-say-the-wording-moved-on"
           Find = 'if ($value.message.saidToEarlierWording) { [void]$lines.Add('
           Replace = 'if ($false) { [void]$lines.Add(' }
        @{ Name = "inbox-does-not-say-a-question-is-closed"
           Find = 'if ("$($item.state)" -cne "open") { $heading = $heading + " [" + $item.state + "]" }'
           Replace = '' }
        @{ Name = "unread-not-counted-in-the-summary"
           Find = 'foreach ($u in @($Thread.unread)) { if ($u.count -gt 0) { $phrase = $phrase + "; " + $u.count + " not yet read by " + $u.readerShown } }'
           Replace = '' }
        @{ Name = "turn-not-said"
           Find = '    return ($phrase + "; turn: " + $Thread.turnShown)'
           Replace = '    return $phrase' }
        @{ Name = "list-says-conversation-of-every-question"
           Find = 'if ($q.thread.count -gt 0) { [void]$lines.Add($pad + "conversation: "'
           Replace = 'if ($true) { [void]$lines.Add($pad + "conversation: "' }
        @{ Name = "show-does-not-print-the-thread"
           Find = '    if ($null -ne $q.thread.PSObject.Properties["messages"]) { $said = @($q.thread.messages) }'
           Replace = '' }
        @{ Name = "show-does-not-say-what-is-unread"
           Find = 'if ($null -ne $who) { [void]$lines.Add("    (not yet read by " + $who.readerShown + ")") }'
           Replace = '' }
        # --- inbox: prints, then marks up to the last record it printed ---
        @{ Name = "inbox-marks-up-to-a-record-it-did-not-print"
           Find = 'request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; upTo = [long]$answer.value.upTo } }'
           Replace = 'request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; upTo = ([long]$answer.value.upTo + 1) } }' }
        @{ Name = "peek-marks"
           Find = '    if ($isInbox -and -not $peek -and $unread -gt 0) {'
           Replace = '    if ($isInbox -and $unread -gt 0) {' }
        @{ Name = "marking-asked-for-with-nothing-unread"
           Find = '    if ($isInbox -and -not $peek -and $unread -gt 0) {'
           Replace = '    if ($isInbox -and -not $peek -and $answer.state -ceq "known") {' }
        @{ Name = "failed-marking-reads-as-done"
           Find = 'if (-not $marking.done) { return [pscustomobject]@{ lines = @(); failure = ("the messages above were NOT marked as read, and will be shown again: " + $marking.reason) } }'
           Replace = 'if (-not $marking.done) { return [pscustomobject]@{ lines = @(); failure = "" } }' }
        @{ Name = "refused-marking-reads-as-done"
           Find = 'if ($answer.value.outcome -ceq "refused") { return [pscustomobject]@{ done = $false; upTo = [long]0; marked = 0; reason = "$($answer.value.reason)" } }'
           Replace = '' }
        @{ Name = "marking-not-said"
           Find = '    $lines = @("", ("Marked as read: " + $marking.marked + " message(s), up to record " + $marking.upTo + "."))'
           Replace = '    $lines = @()' }
        @{ Name = "marking-of-nothing-said-as-a-marking"
           Find = '    if ([int]$marking.marked -eq 0) { $lines ='
           Replace = '    if ($false) { $lines =' }
        # --- inbox -Json never marks; the caller marks with the verb mark-read ---
        @{ Name = "json-inbox-marks-after-its-line"
           Find = '        $after = $null'
           Replace = '' }
        @{ Name = "json-inbox-says-it-marked"
           Find = '-Beside ([ordered]@{ marked = $false; upTo = $shownUpTo }))'
           Replace = '-Beside ([ordered]@{ marked = $true; upTo = $shownUpTo }))' }
        @{ Name = "json-inbox-does-not-say-whether-it-marked"
           Find = '-Beside ([ordered]@{ marked = $false; upTo = $shownUpTo }))'
           Replace = '-Beside ([ordered]@{ upTo = $shownUpTo }))' }
        @{ Name = "json-inbox-does-not-name-its-last-record"
           Find = '        if ($unread -gt 0) { $shownUpTo = [long]$answer.value.upTo }'
           Replace = '' }
        @{ Name = "mark-read-with-no-record-named"
           Find = 'if (-not $have.ContainsKey("UpTo")) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "record-to-mark-up-to-not-checked"
           Find = 'if ($upToText -cnotmatch ''\A[1-9][0-9]{0,9}\z'') { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "mark-read-marks-up-to-another-record"
           Find = '            $request["upTo"] = [long]$upToText'
           Replace = '            $request["upTo"] = [long]$upToText - 1' }
        @{ Name = "marking-of-nothing-said-as-marked"
           Find = '        elseif ([int]$value.marked -eq 0) { [void]$lines.Add("Nothing to mark:'
           Replace = '        elseif ($false) { [void]$lines.Add("Nothing to mark:' }
        @{ Name = "repeated-marking-said-as-new"
           Find = '        if ($value.outcome -ceq "replayed") { [void]$lines.Add("This marking was already recorded'
           Replace = '        if ($false) { [void]$lines.Add("This marking was already recorded' }
        @{ Name = "peek-does-not-say-nothing-was-marked"
           Find = '{ $lines += @("", "Nothing was marked as read (-Peek).") }'
           Replace = '{ }' }
        @{ Name = "empty-inbox-says-nothing"
           Find = 'if ($items.Count -eq 0) { [void]$lines.Add("Nothing unread: nothing has been said that was not already read."); return @($lines) }'
           Replace = 'if ($items.Count -eq 0) { return @($lines) }' }
    )
}
