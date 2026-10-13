# Mutations of the relay port's part in a sender trimming its own stream (relays/Port.ps1, A SENDER
# TRIMS ITS OWN STREAM, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-port-trim.psd1
# Each loosens one thing the port checks or does for a put that carries -KeepFrom, and
# test\test-relay-port.ps1 must fail for every one. Every find string occurs exactly once. The port's
# other rules are test\mutations\relay-port.psd1's.
@{
    Target = "relays\Port.ps1"
    Suite  = "test\test-relay-port.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "trim-may-delete-its-own-put"
           Find = 'if ($KeepFrom -gt $named.seq) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "trim-with-a-key-that-names-no-stream"
           Find = 'if ($null -eq $named) { return (New-HordeUnknown -Reason "the put was not made: it asks to trim a stream'
           Replace = 'if ($null -eq $named) { $named = [pscustomobject]@{ stream = ""; seq = [long]9007199254740991 } }; if ($false) { return (New-HordeUnknown -Reason "the put was not made: it asks to trim a stream' }
        @{ Name = "negative-keep-from-allowed"
           Find = 'if (-not ($KeepFrom -is [int] -or $KeepFrom -is [long]) -or $KeepFrom -lt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "trim-never-reaches-the-relay"
           Find = '$keeping = ($null -ne $Connection.relay.putKeeping)'
           Replace = '$keeping = $false' }
        @{ Name = "relays-trimmed-count-believed"
           Find = 'if ($t.has -and (Test-HordeRelayCursor $t.value)) { $trimmed = [long]$t.value }'
           Replace = 'if ($t.has) { $trimmed = [long]$t.value }' }
        @{ Name = "trimmed-said-when-none-was-asked"
           Find = '$trimmed = [long]-1'
           Replace = '$trimmed = [long]0' }
        @{ Name = "stream-seq-with-a-leading-zero"
           Find = '$script:HordeRelayStreamKeyPattern = ''\A([0-9a-f]{32}/[a-z][a-z0-9-]{0,31}/)([1-9][0-9]{0,15})/'
           Replace = '$script:HordeRelayStreamKeyPattern = ''\A([0-9a-f]{32}/[a-z][a-z0-9-]{0,31}/)([0-9]{1,16})/' }
        @{ Name = "stream-key-not-held-to-its-end"
           Find = '([1-9][0-9]{0,15})/[0-9a-f]{24}\z'''
           Replace = '([1-9][0-9]{0,15})/[0-9a-f]{24}''' }
        @{ Name = "stream-seq-past-the-largest"
           Find = 'if ($n -gt $script:HordeRelaySeqMax) { return $null }'
           Replace = '' }
    )
}
