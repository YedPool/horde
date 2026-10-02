# Mutations of transports/local/Transport.ps1 that only a live far end can show. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-conformance-local.psd1
# test\test-transport-conformance.ps1 must fail for each. Each run takes a minute or two.
@{
    Target = "transports\local\Transport.ps1"
    Suite  = "test\test-transport-conformance.ps1"
    Mutations = @(
        @{ Name = "end-of-stream-read-as-nothing-yet"
           Find = 'if ($n -eq 0) { return [pscustomobject]@{ kind = "eof"'
           Replace = 'if ($n -eq 0) { return [pscustomobject]@{ kind = "none"' }
        @{ Name = "long-read-truncated"
           Find = '[Array]::Copy($st.buf, $copy, $n)'
           Replace = '[Array]::Copy($st.buf, $copy, [Math]::Min($n, 100))' }
    )
}
