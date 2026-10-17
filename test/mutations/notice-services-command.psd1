# Mutations of one line of the notice services' neighbours. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\notice-services-command.psd1
# test\test-notice-services.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "cli\commands\notify.ps1"
    Suite  = "test\test-notice-services.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-service-cap-is-not-passed-on"
           Find = '$r = Submit-HordeNotify -Sender $who -Text $Text -PerHour $perHour'
           Replace = '$r = Submit-HordeNotify -Sender $who -Text $Text' }
    )
}