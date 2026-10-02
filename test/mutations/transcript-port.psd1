# Mutations of core/Transcript.ps1's streaming parts (plan step M2).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\transcript-port.psd1
# Each breaks one rule a second read or a sink depends on; test\test-transcript-port.ps1 must fail for every one.
@{
    Target = "core\Transcript.ps1"
    Suite  = "test\test-transcript-port.ps1"
    Mutations = @(
        @{ Name = "second-read-not-bounded"
           Find = 'while (($null -eq $Upto -or $n -lt $limit) -and'
           Replace = 'while (($true) -and'
           }
        @{ Name = "torn-line-reparsed-on-second-read"
           Find = 'if ($null -ne $Upto -and $n -eq $limit -and $Upto.lastBad) { $pendingBad = $true; continue }'
           Replace = '' }
        @{ Name = "shorter-file-accepted"
           Find = 'if ($null -ne $Upto -and $n -lt $limit) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "stop-ignored"
           Find = 'if ($null -ne $Control -and $Control["stop"] -eq $true) { $stopped = $true; break }'
           Replace = '' }
        @{ Name = "sink-does-not-check"
           Find = '        if ($bad.Count -gt 0) { $this.problem = $bad[0]; throw ("broke the record contract: " + $bad[0]) }'
           Replace = '' }
        @{ Name = "file-order-not-checked"
           Find = '    if ($r.line -lt $PreviousLine) {'
           Replace = '    if ($false) {' }
    )
}
