# Mutations of the analyst settings (core/AnalystRounds.ps1), T-0391 slice 7: the alarm limit and the re-ask cadence are the chat's and the
# doorbell's own by default, and a person's value under the least is refused.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tell-taken-settings.psd1
@{
    Target = "core\AnalystRounds.ps1"
    Suite  = "test\test-analyst-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "analyst-settings-alarm-default"
           Find = '@{ name = "takenAlarmSeconds"; kind = "whole"; default = 90;'
           Replace = '@{ name = "takenAlarmSeconds"; kind = "whole"; default = 91;' }
        @{ Name = "analyst-settings-after-alarm-default"
           Find = '@{ name = "takenAfterAlarmSeconds"; kind = "whole"; default = 300;'
           Replace = '@{ name = "takenAfterAlarmSeconds"; kind = "whole"; default = 301;' }
        @{ Name = "analyst-settings-alarm-min"
           Find = 'default = 90; min = 10; max = 3600'
           Replace = 'default = 90; min = 1; max = 3600' }
    )
}
