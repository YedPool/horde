# Mutations of the relay a listener's forced command runs (transports/local/Relay.ps1, remote plan
# R17a). Run locally, one at a time, through the local gate (the suite is machine-bound):
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\relay-live.psd1
# transports\ssh\test\test-listen-local.ps1 must fail for each.
@{
    Target = "transports\local\Relay.ps1"
    Suite  = "transports\ssh\test\test-listen-local.ps1"
    PassCodes = @(0)
    Mutations = @(
        @{ Name = "no-preamble"
           Find = '$stream.Write($first, 0, $first.Length)'
           Replace = '$null = $first' }
        @{ Name = "lives-on-after-the-hub-closes"
           Find = 'if ($ExitWhenHubCloses) { [HordeLocalRelayEnd]::ExitWhenDone($pump) }'
           Replace = '' }
        @{ Name = "lines-held-until-stdin-ends"
           Find = 'foreach ($line in $Lines) {'
           Replace = 'foreach ($line in @($Lines)) {' }
        @{ Name = "frame-terminator-dropped"
           Find = '$script:HordeLocalRelayAscii.GetBytes("$line" + "`n")'
           Replace = '$script:HordeLocalRelayAscii.GetBytes("$line")' }
    )
}
