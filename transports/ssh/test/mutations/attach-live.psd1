# Mutations of the forced command, cli/attach.ps1 (remote plan R17a; issue #147). Run locally, one at a
# time, through the local gate (the suite is machine-bound):
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\attach-live.psd1
# transports\ssh\test\test-listen-local.ps1 must fail for each.
@{
    Target = "cli\attach.ps1"
    Suite  = "transports\ssh\test\test-listen-local.ps1"
    PassCodes = @(0)
    Mutations = @(
        @{ Name = "second-link-admitted"
           Find = 'if (-not $held) { throw'
           Replace = 'if ($false) { throw' }
    )
}
