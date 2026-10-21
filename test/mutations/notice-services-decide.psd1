# Mutations of one line of the notice services' neighbours. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\notice-services-decide.psd1
# test\test-notice-services.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "notices\Decide.ps1"
    Suite  = "test\test-notice-services.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-service-is-shown-as-a-session"
           Find = '$fromWords = $(if ($from.refused) { $(if ($isService) { "a service" } else { "a session" }) } else { $from.text })'
           Replace = '$fromWords = $(if ($from.refused) { "a session" } else { $from.text })' }
        @{ Name = "a-service-cutoff-says-session"
           Find = '$(if ($isService) { "service" } else { "session" }) + " has sent "'
           Replace = '"session" + " has sent "' }
    )
}