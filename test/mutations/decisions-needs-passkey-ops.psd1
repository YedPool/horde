# Mutations of decisions/Operations.ps1 where the list holds to the passkey rule for production actions
# (audit of 2026-10-16, item 17; review of PR 324): an answer to a needs-passkey question is written only
# with a proven passkey signature, and the operation authorized proves the standing answer again, asks
# the journal for a later one, and goes ahead only on a plain yes - to every part of a question of parts.
# Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-needs-passkey-ops.psd1
# Each breaks one half of it; test\test-decisions-needs-passkey.ps1 must fail for every one.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-needs-passkey.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- at the write ---
        @{ Name = "a-needs-passkey-answer-is-not-proven"
           Find = '        if ((Test-HordeDecisionMember -Object $asked -Name "needsPasskey") -and [bool]$asked["needsPasskey"]) {'
           Replace = '        if ($false) {' }
        @{ Name = "the-proof-is-asked-and-ignored"
           Find = '            if (-not $proof.ok) { return [pscustomobject]@{ why = (Get-HordeDecisionPasskeyRefusal'
           Replace = '            if ($false) { return [pscustomobject]@{ why = (Get-HordeDecisionPasskeyRefusal' }
        @{ Name = "his-act-must-be-proven-too"
           Find = '-ceq (Get-HordeDecisionFirstTurn) -and -not $Data.Contains("act") -and $List.questions.ContainsKey($number)) {'
           Replace = '-ceq (Get-HordeDecisionFirstTurn) -and $List.questions.ContainsKey($number)) {' }
        @{ Name = "the-keepers-words-must-be-proven-too"
           Find = '    if ("$($Data[''speaker''])" -ceq (Get-HordeDecisionFirstTurn) -and -not $Data.Contains("act")'
           Replace = '    if ($true -and -not $Data.Contains("act")' }
        @{ Name = "the-write-proves-from-HORDE_HOME-not-the-stores-home"
           Find = '            $step = & $entry.complete $Request $list $data $Root $Now'
           Replace = '            $step = & $entry.complete $Request $list $data' }
        @{ Name = "the-proof-file-is-never-loaded"
           Find = '-CommandType Function -ErrorAction SilentlyContinue)) { . $script:HordeDecisionPasskeyProofFile }'
           Replace = '-CommandType Function -ErrorAction SilentlyContinue)) { }' }
        @{ Name = "every-store-is-in-HORDE_HOME"
           Find = '    return [System.IO.Path]::GetDirectoryName($store)'
           Replace = '    return ""' }
        # --- authorized: the standing answer, proven ---
        @{ Name = "authorized-of-a-question-that-is-not-there-is-a-refusal"
           Find = '    if ($null -ne $notThere) { return $notThere }'
           Replace = '' }
        @{ Name = "authorized-trusts-the-record"
           Find = '        if (-not $proof.ok) { return (& $no ($at + " is not proven signed by a passkey this machine trusts: " + $proof.reason)) }'
           Replace = '' }
        @{ Name = "authorized-does-not-ask-the-route"
           Find = '        if ("$($standing.route)" -cne "phone") {'
           Replace = '        if ($false) {' }
        @{ Name = "authorized-takes-an-answer-to-an-old-wording"
           Find = '        if (-not [bool]$standing.wordingStated -or [int]$standing.wordingVersion -ne [int]$question.wordingVersion) {'
           Replace = '        if ($false) {' }
        @{ Name = "an-act-is-the-standing-answer"
           Find = '-ceq (Get-HordeDecisionFirstTurn) -and "$($m.act)" -ceq "" -and $answers -ccontains "$($m.part)") { $standing = $m } }'
           Replace = '-ceq (Get-HordeDecisionFirstTurn) -and $answers -ccontains "$($m.part)") { $standing = $m } }' }
        @{ Name = "his-first-answer-is-the-standing-one"
           Find = '-and "$($m.act)" -ceq "" -and $answers -ccontains "$($m.part)") { $standing = $m } }'
           Replace = '-and "$($m.act)" -ceq "" -and $answers -ccontains "$($m.part)" -and $null -eq $standing) { $standing = $m } }' }
        @{ Name = "authorized-proves-from-HORDE_HOME-not-the-stores-home"
           Find = '    return (& $entry.read $plain $read.list $definitions $Now $Root)'
           Replace = '    return (& $entry.read $plain $read.list $definitions $Now)' }
        @{ Name = "authorized-does-not-ask-the-journal-for-a-later-answer"
           Find = '-Root $Root -Now $Now -LaterParts $answers -LaterAnyPart:($part -ceq "")'
           Replace = '-Root $Root -Now $Now' }
        # --- authorized: only a plain yes ---
        @{ Name = "a-proven-no-authorizes"
           Find = '        if (-not (Test-HordeDecisionPlainYes -Text ([string]$standing.text))) {'
           Replace = '        if ($false) {' }
        @{ Name = "any-kind-of-question-authorizes"
           Find = '    if ($script:HordeDecisionYesKinds -cnotcontains $kind) {'
           Replace = '    if ($false) {' }
        @{ Name = "a-yes-may-go-on-after-the-word"
           Find = '$script:HordeDecisionPlainYes = ''\A[Yy][Ee][Ss][.!]?\z'''
           Replace = '$script:HordeDecisionPlainYes = ''\A[Yy][Ee][Ss]''' }
        @{ Name = "a-yes-may-end-in-a-question-mark"
           Find = '$script:HordeDecisionPlainYes = ''\A[Yy][Ee][Ss][.!]?\z'''
           Replace = '$script:HordeDecisionPlainYes = ''\A[Yy][Ee][Ss][.!?]?\z''' }
        @{ Name = "any-white-space-is-trimmed"
           Find = '    return ($Text.Trim([char[]]@([char]32, [char]9, [char]10, [char]13)) -cmatch $script:HordeDecisionPlainYes)'
           Replace = '    return ($Text.Trim() -cmatch $script:HordeDecisionPlainYes)' }
        @{ Name = "the-whole-question-asked-checks-only-its-own-parts-in-the-journal"
           Find = ' -LaterParts $answers -LaterAnyPart:($part -ceq "")'
           Replace = ' -LaterParts $answers' }
        # --- authorized: parts ---
        @{ Name = "a-part-that-is-not-there-is-asked-anyway"
           Find = '    if ($part -cne "" -and $letters -cnotcontains $part) {'
           Replace = '    if ($false) {' }
        @{ Name = "the-whole-of-a-question-of-parts-is-its-whole-answer-alone"
           Find = '    $targets = @($(if ($part -cne "") { $part } elseif ($letters.Count -gt 0) { $letters } else { "" }))'
           Replace = '    $targets = @($(if ($part -cne "") { $part } else { "" }))' }
        @{ Name = "an-answer-to-the-whole-does-not-stand-for-a-part"
           Find = '        $answers = @(@($p, "") | Select-Object -Unique)'
           Replace = '        $answers = @($p)' }
    )
}
