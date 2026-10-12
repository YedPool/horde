# Mutations of decisions/Rules.ps1's route phone and its evidence (relay design 2026-10-09, PR plan
# item 5). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-phone-route.psd1
# Each loosens one rule of the route; test\test-decisions-phone-route.ps1 must fail for every one.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-phone-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the route's closed list ---
        @{ Name = "warchief-speaks-by-phone"
           Find = '"phone"         = @{ speakers = @("founder");  actors = @("founder");'
           Replace = '"phone"         = @{ speakers = @("founder", "warchief");  actors = @("founder");' }
        @{ Name = "warchief-records-phone-words"
           Find = '"phone"         = @{ speakers = @("founder");  actors = @("founder");'
           Replace = '"phone"         = @{ speakers = @("founder");  actors = @("founder", "warchief");' }
        @{ Name = "phone-need-not-state-wording"
           Find = 'shown = "answered on the founder''s phone";    statesWording = $true; evidence = $true }'
           Replace = 'shown = "answered on the founder''s phone";    statesWording = $false; evidence = $true }' }
        @{ Name = "phone-shown-as-the-window"
           Find = 'shown = "answered on the founder''s phone";'
           Replace = 'shown = "typed in the window";' }
        # --- the evidence ---
        @{ Name = "phone-needs-no-evidence"
           Find = 'statesWording = $true; evidence = $true }'
           Replace = 'statesWording = $true; evidence = $false }' }
        @{ Name = "missing-evidence-not-refused"
           Find = 'if ($needsEvidence -and -not $EvidenceStated) {'
           Replace = 'if ($false) {' }
        @{ Name = "evidence-on-another-route-not-refused"
           Find = 'if (-not $needsEvidence -and $EvidenceStated) {'
           Replace = 'if ($false) {' }
        @{ Name = "evidence-kept-off-the-message"
           Find = 'evidence = $(if (Test-HordeDecisionMember -Object $Ev.data -Name "evidence") { [string]$Ev.data.evidence } else { "" })'
           Replace = 'evidence = ""' }
        @{ Name = "evidence-shown-from-nothing"
           Find = '        evidence = "$($Message.evidence)"'
           Replace = '        evidence = ""' }
        # --- who signed (signedBy, 2026-10-12) ---
        @{ Name = "signedBy-on-another-route-not-refused"
           Find = 'if (-not $needsEvidence -and $SignedByStated) {'
           Replace = 'if ($false) {' }
        @{ Name = "signedBy-in-any-spelling-taken-by-the-rules"
           Find = 'if ($SignedByStated -and $SignedBy -cnotmatch $script:HordeDecisionSignedByPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "signedBy-pattern-takes-upper-case"
           Find = '$script:HordeDecisionSignedByPattern = ''\A[0-9a-f]{32}\z'''
           Replace = '$script:HordeDecisionSignedByPattern = ''\A[0-9a-fA-F]{32}\z''' }
        @{ Name = "signedBy-pattern-not-anchored-at-the-end"
           Find = '$script:HordeDecisionSignedByPattern = ''\A[0-9a-f]{32}\z'''
           Replace = '$script:HordeDecisionSignedByPattern = ''\A[0-9a-f]{32}''' }
        @{ Name = "signedBy-kept-off-the-message"
           Find = 'signedBy = $(if (Test-HordeDecisionMember -Object $Ev.data -Name "signedBy") { [string]$Ev.data.signedBy } else { "" })'
           Replace = 'signedBy = ""' }
        @{ Name = "signedBy-shown-from-nothing"
           Find = '        signedBy = "$($Message.signedBy)"'
           Replace = '        signedBy = ""' }
        @{ Name = "signer-named-on-any-route"
           Find = 'if ($null -eq $entry -or -not ($entry.ContainsKey("evidence") -and [bool]$entry.evidence)) { return (& $none'
           Replace = 'if ($false) { return (& $none' }
        @{ Name = "signer-named-on-an-unknown-route"
           Find = 'if ($null -eq $entry -or -not ($entry.ContainsKey("evidence") -and [bool]$entry.evidence)) { return (& $none'
           Replace = 'if ($null -ne $entry -and -not ($entry.ContainsKey("evidence") -and [bool]$entry.evidence)) { return (& $none' }
        @{ Name = "signer-named-without-evidence"
           Find = 'if ($Evidence -cnotmatch $script:HordeDecisionEvidencePattern) { return (& $none'
           Replace = 'if ($false) { return (& $none' }
        @{ Name = "signer-key-id-in-any-spelling"
           Find = 'if ($SignedBy -cnotmatch $script:HordeDecisionSignedByPattern) { return (& $none'
           Replace = 'if ($SignedBy -ceq "") { return (& $none' }
        @{ Name = "old-record-not-told-apart"
           Find = 'if ($SignedBy -ceq "") { return (& $none "their record names no passkey: it was written before records did") }'
           Replace = '' }
    )
}
