# Mutations of the analyst command's tools (cli/commands/analyst.ps1), T-0391 slice 7: the warchief is told through the marked teller, and the
# look at the awaiting list is a tool of the same pass.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tell-taken-command.psd1
@{
    Target = "cli\commands\analyst.ps1"
    Suite  = "test\test-analyst-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "analyst-command-tell-unmarked"
           Find = 'return (Send-HordeAnalystWarchiefTaken -Key $Key'
           Replace = 'return (Send-HordeAnalystWarchief -Key $Key' }
        @{ Name = "analyst-command-look-tool-missing"
           Find = '$tools["TellTaken"] = {'
           Replace = '$tools["TellTakenOff"] = {' }
        @{ Name = "analyst-command-relay-tell-marked"
           Find = '$relayTools["Tell"] = { param($Body) return (Send-HordeAnalystWarchief -Key "relay"'
           Replace = '$relayTools["Tell"] = { param($Body) return (Send-HordeAnalystWarchiefTaken -Key "relay"' }
    )
}
