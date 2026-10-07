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
           Find = 'foreach ($l in @(([string]$Message.text) -split "\r?\n")) { [void]$lines.Add($Indent + "    " + $l) }'
           Replace = 'foreach ($l in @(([string]$Message.text) -split "\r?\n" | Where-Object { $_.Trim() -ne "" })) { [void]$lines.Add($Indent + "    " + $l) }' }
        @{ Name = "lines-of-the-words-trimmed-when-printed"
           Find = 'foreach ($l in @(([string]$Message.text) -split "\r?\n")) { [void]$lines.Add($Indent + "    " + $l) }'
           Replace = 'foreach ($l in @(([string]$Message.text) -split "\r?\n")) { [void]$lines.Add($Indent + "    " + $l.Trim()) }' }
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
        # --- inbox: prints, then marks what it printed ---
        @{ Name = "inbox-marks-everything-unread-not-what-it-printed"
           Find = 'request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; mark = $true; upTo = [long]$answer.value.upTo } }'
           Replace = 'request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; mark = $true } }' }
        @{ Name = "peek-marks"
           Find = 'if ($Verb -ceq "inbox" -and -not $peek -and $answer.state -ceq "known"'
           Replace = 'if ($Verb -ceq "inbox" -and $answer.state -ceq "known"' }
        @{ Name = "inbox-marks-in-the-same-call-as-it-reads"
           Find = '    if ($Verb -ceq "inbox") { $writes = $false }'
           Replace = '    if ($Verb -ceq "inbox") { $writes = $false; $request["mark"] = $true; $request["id"] = $id }' }
        @{ Name = "failed-marking-reads-as-done"
           Find = 'if ($answer.state -cne "known") { return [pscustomobject]@{ lines = @(); failure = ("the messages above were NOT marked as read, and will be shown again: " + $answer.reason) } }'
           Replace = 'if ($answer.state -cne "known") { return [pscustomobject]@{ lines = @(); failure = "" } }' }
        @{ Name = "marking-not-said"
           Find = 'if (-not [bool]$After.quiet) { $lines = @("", ("Marked as read: "'
           Replace = 'if ($false) { $lines = @("", ("Marked as read: "' }
        @{ Name = "marking-of-nothing-said-as-a-marking"
           Find = 'if (-not [bool]$After.quiet -and [int]$answer.value.marked -eq 0) { $lines ='
           Replace = 'if ($false) { $lines =' }
        @{ Name = "json-inbox-prints-a-second-line"
           Find = '$after = [pscustomobject]@{ operation = "inbox"; quiet = $asJson'
           Replace = '$after = [pscustomobject]@{ operation = "inbox"; quiet = $false' }
        @{ Name = "peek-does-not-say-nothing-was-marked"
           Find = '{ $lines += @("", "Nothing was marked as read (-Peek).") }'
           Replace = '{ }' }
        @{ Name = "empty-inbox-says-nothing"
           Find = 'if ($items.Count -eq 0) { [void]$lines.Add("Nothing unread: nothing has been said that was not already read."); return @($lines) }'
           Replace = 'if ($items.Count -eq 0) { return @($lines) }' }
    )
}
