# Mutations of decisions/Operations.ps1 where the list holds to the passkey rule for production actions
# (audit of 2026-10-16, item 17): an answer to a needs-passkey question is written only with a proven
# passkey signature, and the operation authorized proves the standing answer again. Run:
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
        # --- authorized ---
        @{ Name = "authorized-of-a-question-that-is-not-there-is-a-refusal"
           Find = '    if ($null -ne $notThere) { return $notThere }'
           Replace = '' }
        @{ Name = "authorized-trusts-the-record"
           Find = '    if (-not $proof.ok) { return (& $no ($at + " is not proven signed by a passkey this machine trusts: " + $proof.reason)) }'
           Replace = '' }
        @{ Name = "authorized-does-not-ask-the-route"
           Find = '    if ("$($standing.route)" -cne "phone") {'
           Replace = '    if ($false) {' }
        @{ Name = "authorized-takes-an-answer-to-an-old-wording"
           Find = '    if (-not [bool]$standing.wordingStated -or [int]$standing.wordingVersion -ne [int]$question.wordingVersion) {'
           Replace = '    if ($false) {' }
        @{ Name = "an-act-is-the-standing-answer"
           Find = '-ceq (Get-HordeDecisionFirstTurn) -and "$($m.act)" -ceq "" -and "$($m.part)" -ceq $part) { $standing = $m } }'
           Replace = '-ceq (Get-HordeDecisionFirstTurn) -and "$($m.part)" -ceq $part) { $standing = $m } }' }
        @{ Name = "his-first-answer-is-the-standing-one"
           Find = '-and "$($m.act)" -ceq "" -and "$($m.part)" -ceq $part) { $standing = $m } }'
           Replace = '-and "$($m.act)" -ceq "" -and "$($m.part)" -ceq $part -and $null -eq $standing) { $standing = $m } }' }
        @{ Name = "authorized-proves-from-HORDE_HOME-not-the-stores-home"
           Find = '    return (& $entry.read $plain $read.list $definitions $Now $Root)'
           Replace = '    return (& $entry.read $plain $read.list $definitions $Now)' }
    )
}
