# Mutations of decisions/Console.ps1 (the verb change-reply, and how show tells a change) for THE FOUNDER
# CHANGES HIS ANSWER (T-0152). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-change-console.psd1
# test\test-decisions-change.ps1 must fail for each. Each find string occurs once. The notice to the Orc
# (decisions/Route.ps1) is decisions-change-route.psd1.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\test-decisions-change.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-session-is-taken-for-the-warchief"
           Find = '        if ($null -eq $held -or -not [bool]$held.ok) { return [pscustomobject]@{ ok = $false; reason = "this session does not hold the warchief''s seat" } }'
           Replace = '' }
        @{ Name = "a-session-that-cannot-be-proven-is-taken-for-the-warchief"
           Find = '        if ($null -eq $who -or -not [bool]$who.ok) { return [pscustomobject]@{ ok = $false; reason = "which session this is could not be proven" } }'
           Replace = '' }
        @{ Name = "the-proven-seat-is-not-sent-to-the-operation"
           Find = '{ $request["callerSeat"] = "warchief" }'
           Replace = '{ }' }
        @{ Name = "the-keepers-list-line-shows-his-chat-words-as-his-answer"
           Find = ' -and (Test-HordeDecisionMessageAuthorizes -Message $_) })'
           Replace = ' })' }
        @{ Name = "show-tells-chat-words-as-replacing-his-answer"
           Find = ' -and "$($Message.speaker)" -ceq "founder" -and (Test-HordeDecisionMessageAuthorizes -Message $Message)) {'
           Replace = ' -and "$($Message.speaker)" -ceq "founder") {' }
        @{ Name = "a-session-that-is-no-orc-may-reply"
           Find = '    if ("$($who.label)" -cnotmatch ''\A[A-Z]\z'') {'
           Replace = '    if ($false) {' }
        @{ Name = "a-session-that-does-not-hold-the-orcs-seat-may-reply"
           Find = '    if ($null -eq $held -or -not [bool]$held.ok) { throw ('
           Replace = '    if ($false) { throw (' }
        @{ Name = "a-session-that-cannot-be-proven-may-reply"
           Find = '    if ($null -eq $who -or -not [bool]$who.ok) { throw ('
           Replace = '    if ($false) { throw (' }
        @{ Name = "the-reply-is-not-required"
           Find = '            if (-not $have.ContainsKey("Reply")) { throw ('
           Replace = '            if ($false) { throw (' }
        @{ Name = "the-changed-answer-is-not-required"
           Find = '            if ($have.ContainsKey("Answer") -eq $false) { throw ("decisions change-reply needs -Answer <record>'
           Replace = '            if ($false) { throw ("decisions change-reply needs -Answer <record>' }
        @{ Name = "a-changed-answer-that-is-no-record-number-is-taken"
           Find = '            if ($changeText -cnotmatch ''\A[1-9][0-9]{0,9}\z'') {'
           Replace = '            if ($false) {' }
        @{ Name = "a-reason-may-be-more-than-a-line"
           Find = '                if ($whyText -match "[\r\n]") { throw ("-Why is one line" + $usageNote) }'
           Replace = '' }
        @{ Name = "the-reason-is-not-handed-on"
           Find = '                $request["why"] = $whyText'
           Replace = '' }
        @{ Name = "show-does-not-mark-a-changed-answer"
           Find = '    if ((& $has "changedFrom") -and [long]$Message.changedFrom -ge 1) {'
           Replace = '    if ($false) {' }
        @{ Name = "show-leaves-out-the-words-a-change-replaced"
           Find = '        foreach ($oldLine in @(([string]$Message.changedFromText) -split "\r\n|\r|\n")) { [void]$lines.Add($Indent + "      > " + $oldLine) }'
           Replace = '' }
        @{ Name = "show-says-nothing-of-what-became-of-a-change"
           Find = '        foreach ($c in @($q.answerChanges)) {'
           Replace = '        foreach ($c in @()) {' }
        @{ Name = "show-leaves-out-why-the-work-cannot-be-undone"
           Find = ' + $(if ("$($c.reply.why)" -ne "") { ": " + $c.reply.why } else { "" })'
           Replace = ' + ""' }
        @{ Name = "show-does-not-say-it-waits-for-the-orc"
           Find = '            $state = "no reply yet from " + $(if ("$($c.orcShown)" -ne "") { $c.orcShown } else { "anyone: no Orc asked this question" })'
           Replace = '            $state = ""' }
        # --- N1: his words are cut at every kind of line break
        @{ Name = "show-cuts-the-old-words-at-lf-only"
           Find = '-split "\r\n|\r|\n")) { [void]$lines.Add($Indent + "      > " + $oldLine) }'
           Replace = '-split "\r?\n")) { [void]$lines.Add($Indent + "      > " + $oldLine) }' }
        @{ Name = "show-cuts-the-message-text-at-lf-only"
           Find = '-split "\r\n|\r|\n")) { [void]$lines.Add($Indent + "    " + $l) }'
           Replace = '-split "\r?\n")) { [void]$lines.Add($Indent + "    " + $l) }' }
        @{ Name = "answer-does-not-say-chat-words-are-no-passkey-answer"
           Find = '        if ($null -ne $value.message.PSObject.Properties["notPasskey"] -and [bool]$value.message.notPasskey) {'
           Replace = '        if ($false) {' }
    )
}
