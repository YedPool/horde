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
    )
}
