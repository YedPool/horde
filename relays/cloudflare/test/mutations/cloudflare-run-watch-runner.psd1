# One mutation of the runner (cli/RelayRun.ps1, relay PR 8c): a relay's declared run watch is the run's
# watch on it. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-run-watch-runner.psd1
# relays\cloudflare\test\test-cloudflare-limits.ps1 must fail for it. Every find string occurs once.
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-limits.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "declared-run-watch-ignored"
           Find = 'if ($null -ne $declared -and [int]$declared.Value -gt 0) { return [int]$declared.Value }'
           Replace = '' }
    )
}
