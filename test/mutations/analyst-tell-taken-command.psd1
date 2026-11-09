# Mutations of the analyst command's tools (cli/commands/analyst.ps1), T-0391 slice 7: the warchief is told through the marked teller, and the
# look at the awaiting list is a tool of the same pass.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tell-taken-command.psd1
@{
    Target = "cli\commands\analyst.ps1"
    Suite  = "test\test-analyst-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "analyst-command-look-tool-missing"
           Find = '$tools["TellTaken"] = {'
           Replace = '$tools["TellTakenOff"] = {' }
        # Round 2, item 5: the three mutants a reviewer's own run left alive, and the second load.
        @{ Name = "analyst-command-tell-drops-the-generation"
           Find = '-Values $Values -Gen ([long]$Gen) -HordeHome $hordeHome) }'
           Replace = '-Values $Values -HordeHome $hordeHome) }' }
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
           Find = 'Get-HordeAnalystNoticeWatch -HordeHome $hordeHome -Key $Key -Gen ([long]$Gen)) }'
           Replace = 'Get-HordeAnalystNoticeWatch -HordeHome $hordeHome -Key $Key -Gen 0) }' }
        # T-0391 slice 8: the relay watch's and the watcher check's tools are marked too, and the watcher check has both.
        @{ Name = "analyst-command-relay-tell-skips-the-watch-teller"
           Find = '$relayTools["Tell"] = { param($Body, $Key, $Gen) return (Send-HordeAnalystWatchTell -Key $Key'
           Replace = '$relayTools["Tell"] = { param($Body, $Key, $Gen) return (Send-HordeAnalystWarchiefTaken -Key $Key' }
        @{ Name = "analyst-command-relay-tell-drops-the-generation"
           Find = '-Values $policy.values -Gen ([long]$Gen) -HordeHome $hordeHome) }'
           Replace = '-Values $policy.values -HordeHome $hordeHome) }' }
        @{ Name = "analyst-command-relay-taken-tool-missing"
           Find = '$relayTools["Taken"] = {'
           Replace = '$relayTools["TakenOff"] = {' }
        @{ Name = "analyst-command-relay-taken-ignores-the-generation"
           Find = 'Get-HordeAnalystWatchTaken -HordeHome $hordeHome -Key $Key -Gen ([long]$Gen)'
           Replace = 'Get-HordeAnalystWatchTaken -HordeHome $hordeHome -Key $Key -Gen 0' }
        @{ Name = "analyst-command-watcher-check-has-no-taken-tool"
           Find = 'Taken = $relayTools["Taken"]; Notify = $relayTools["Notify"] }'
           Replace = 'Notify = $relayTools["Notify"] }' }
    )
}
