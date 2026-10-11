# Mutations of the run watch outside the hosted relay's own folder (relay PR 8c): the port keeps a
# relay's declared run watch, and the runner uses it. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-run-watch.psd1
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-run-watch-runner.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for every one: its fleet check computes an
# always-on machine's day through the port and the runner. Every find string occurs once.
#
# NOT HERE, and why: the port's refusal of a run watch past the relay's maxWatchMs (the one relay that
# declares one declares a valid one, so no suite meets the refusal).
@{
    Target = "relays\Port.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "declared-run-watch-dropped"
           Find = 'deploy = $Deploy; runWatchMs = $RunWatchMs }'
           Replace = 'deploy = $Deploy; runWatchMs = 0 }' }
    )
}
