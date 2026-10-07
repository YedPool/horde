# Mutations of decisions/Rules.ps1 that only separate processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-threads-race-rules.psd1
# test\test-decisions-threads-race.ps1 must fail for each: with either, a say that loses its place to
# a close of its question is refused, and the words are gone.
@{
    Target = "decisions\Rules.ps1"
    Suite  = "test\test-decisions-threads-race.ps1"
    Mutations = @(
        @{ Name = "words-under-a-closed-question-dropped"
           Find = '    $seen = [int]$Ev.data.wordingVersion'
           Replace = '    if ($question.state -cne "open") { return "the question is closed" }; $seen = [int]$Ev.data.wordingVersion' }
        @{ Name = "arrival-after-closing-not-flagged"
           Find = '        arrivedAfterClosing = [bool]($question.state -cne "open")'
           Replace = '        arrivedAfterClosing = $false' }
    )
}
