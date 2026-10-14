# Mutations of the remind operation (decisions/Operations.ps1), held by the scenario at the real
# command line. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-asked-operations.psd1
# test\e2e\e2e-decisions-asked.ps1 must fail for each. It exits 3 (PARTIAL) where Node is missing;
# that is not accepted here: the page's order is part of what it holds.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\e2e\e2e-decisions-asked.ps1"
    Mutations = @(
        @{ Name = "the-note-is-not-checked"
           Find = '        $found = @(Test-HordeDecisionAskedNote -Text (Get-HordeDecisionMember -Object $Request -Name "note"))'
           Replace = '        $found = @()' }
        @{ Name = "the-note-is-not-recorded"
           Find = '        $body["note"] = [string]$Request.note'
           Replace = '' }
        @{ Name = "remind-is-no-operation"
           Find = '    remind = @{ writes = $true;  kind = "question-reminded"; content = "Get-HordeDecisionRemindContent" }'
           Replace = '' }
    )
}
