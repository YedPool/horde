# Mutations of transports/memory/Transport.ps1, the in-process pair, against the conformance suite.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-conformance-memory.psd1
# test\test-transport-conformance.ps1 must fail for each. Each run takes a minute or two.
@{
    Target = "transports\memory\Transport.ps1"
    Suite  = "test\test-transport-conformance.ps1"
    Mutations = @(
        @{ Name = "declined-peer-claimed-verified"
           Find = 'return [pscustomobject]@{ verified = $false; identity = ""; how = "in-process: the far end is not identified (auth.peer declined)" }'
           Replace = 'return [pscustomobject]@{ verified = $true; identity = "in-process"; how = "assumed" }' }
        @{ Name = "close-not-seen-by-far-end"
           Find = '$Channel.state.outbound.writerClosed = $true'
           Replace = '$null = 0' }
    )
}
