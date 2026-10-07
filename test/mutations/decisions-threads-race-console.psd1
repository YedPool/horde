# Mutations of decisions/Console.ps1 that only separate processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-threads-race-console.psd1
# test\test-decisions-threads-race.ps1 must fail: with it, `horde decisions inbox` marks everything
# unread at the moment of marking, and a message that another process said after the printing is
# marked read without ever having been printed.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\test-decisions-threads-race.ps1"
    Mutations = @(
        @{ Name = "inbox-marks-everything-unread-not-what-it-printed"
           Find = 'request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; mark = $true; upTo = [long]$answer.value.upTo } }'
           Replace = 'request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; mark = $true } }' }
    )
}
