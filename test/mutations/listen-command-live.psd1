# Mutations of horde listen's watch loop (cli/commands/listen.ps1; remote plan R17a, issue #147 item 4).
# Run locally, one at a time (the suite is machine-bound):
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\listen-command-live.psd1
# transports\ssh\test\test-listen-local.ps1 must fail for each. The adapter's health check answers
# unknown once authorized_keys stops holding every key to attach (transports/ssh/Listen.ps1,
# Test-HordeSshListenerServing); only this loop turns that answer into a stopped listener, and
# listen.psd1's keys-not-rechecked covers the adapter's half alone, in a pure suite.
@{
    Target = "cli\commands\listen.ps1"
    Suite  = "transports\ssh\test\test-listen-local.ps1"
    PassCodes = @(0)
    Mutations = @(
        @{ Name = "unknown-health-keeps-listening"
           Find = 'if ($h.state -cne "known" -or $h.value -ne $true) {'
           Replace = 'if ($h.state -ceq "known" -and $h.value -ne $true) {' }
    )
}
