# Mutations of decisions/Operations.ps1 that only separate processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-threads-race.psd1
# test\test-decisions-threads-race.ps1 must fail for each. The mutants of the rules and of the command
# that the same suite sees are test\mutations\decisions-threads-race-rules.psd1: a spec has one target.
#
# Each run of the suite starts ten powershell.exe processes, two at a time, and takes about a minute
# and a half on a throttled machine.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-threads-race.ps1"
    Mutations = @(
        @{ Name = "marked-up-to-the-end-of-the-list"
           Find = '    $upTo = [long]$Data["upTo"]'
           Replace = '    $upTo = [long]$List.lastSequence' }
        @{ Name = "repost-answered-without-what-it-recorded"
           Find = 'if ($entry.ContainsKey("parts")) { $again = & $entry.parts $list ([long]$prior.sequence); foreach ($k in @($again.Keys)) { $more[$k] = $again[$k] } }'
           Replace = '' }
    )
}
