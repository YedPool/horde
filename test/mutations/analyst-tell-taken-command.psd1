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
        # Round 2, item 5: the three mutants a reviewer's own run left alive, and the second load.
        @{ Name = "analyst-command-tell-drops-the-generation"
           Find = '-Gen ([long]$Gen) -HordeHome $hordeHome) }'
           Replace = '-HordeHome $hordeHome) }' }
        @{ Name = "analyst-command-look-ignores-the-alarm-setting"
           Find = '-AlarmSeconds ([double]$Values.takenAlarmSeconds)'
           Replace = '-AlarmSeconds 90' }
        @{ Name = "analyst-command-look-ignores-the-cadence-setting"
           Find = '-AfterAlarmSeconds ([double]$Values.takenAfterAlarmSeconds)'
           Replace = '-AfterAlarmSeconds 300' }
        @{ Name = "analyst-command-never-loads-the-messengers"
           Find = 'foreach ($f in @(Get-HordeMessengerFiles)) { . $f }'
           Replace = '$null = 0' }
        # A second load of the messenger port by one of the tools throws "already registered" (PR 430, round 1): the suite must FAIL a check, not break.
        @{ Name = "analyst-command-look-loads-the-messengers-again"
           Find = 'param($Values)'
           Replace = 'param($Values); foreach ($f in @(Get-HordeMessengerFiles)) { . $f }' }
        # Round 3, item 3: the tool the pass asks whether a notice is still watched.
        @{ Name = "analyst-command-watching-tool-missing"
           Find = '$tools["Watching"] = {'
           Replace = '$tools["WatchingOff"] = {' }
        @{ Name = "analyst-command-watching-ignores-the-generation"
           Find = '-Key $Key -Gen ([long]$Gen)) }'
           Replace = '-Key $Key -Gen 0) }' }
        @{ Name = "analyst-command-relay-tell-marked"
           Find = '$relayTools["Tell"] = { param($Body) return (Send-HordeAnalystWarchief -Key "relay"'
           Replace = '$relayTools["Tell"] = { param($Body) return (Send-HordeAnalystWarchiefTaken -Key "relay"' }
    )
}
