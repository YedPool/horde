# Mutations of decisions/Operations.ps1 for the operations route and ack and the list's flag. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-route-operations.psd1
# test\test-decisions-route.ps1 must fail for each.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "an-ack-that-names-no-answer-records-none"
           Find = '$Data["answer"] = [long]$standing.sequence'
           Replace = '' }
        @{ Name = "the-list-without-its-flag"
           Find = 'counts = [pscustomobject]$counts; unclosed = $unclosed })'
           Replace = 'counts = [pscustomobject]$counts; unclosed = @() })' }
        @{ Name = "the-hour-is-not-the-setting"
           Find = '-Minutes (Get-HordeDecisionSetting -Name "decisions.answers.unclosedMinutes")'
           Replace = '-Minutes 0' }
        @{ Name = "a-route-note-of-two-lines"
           Find = 'foreach ($f in @(Test-HordeDecisionNote -Text $line -Name $name -OneLine)) { [void]$found.Add($f) }'
           Replace = '' }
    )
}
