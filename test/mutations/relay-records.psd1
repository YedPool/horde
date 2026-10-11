# Mutations of relay/Records.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-records.psd1
# Each loosens how a write-once record is read back, and test\test-relay-pairing.ps1 - which damages
# records on disk one way at a time - must fail for every one. Every find string occurs once in the
# target.
@{
    Target = "relay\Records.ps1"
    Suite  = "test\test-relay-pairing.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "point-not-validated"
           Find = 'try { $k = ConvertFrom-HordeRelayP256Public -Bytes $bytes -Use "ecdsa"; $k.Dispose() }'
           Replace = 'try { }' }
        @{ Name = "end-not-anchored"
           Find = '+ "\}\z"'
           Replace = '+ "\}"' }
        @{ Name = "foreign-file-ignored"
           Find = 'if ($it.PSIsContainer -or $n -cnotmatch $Pattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "temporary-file-not-passed-over"
           Find = 'if ($n -cmatch ''\Awriting-[0-9a-f]{32}\.part\z'') { continue }'
           Replace = 'if ($false) { continue }' }
    )
}
