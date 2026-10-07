# The registry of core/Transcript.ps1 is made once and survives a second load of the file (review of #114). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\core-load-registry-transcript.psd1
# test\test-core-load.ps1 must fail: a reset on every load empties what registered before.
@{
    Target = "core\Transcript.ps1"
    Suite  = "test\test-core-load.ps1"
    Mutations = @(
        @{ Name = "registry-reset-on-load"
           Find = 'if ($null -eq (Get-Variable -Name HordeTranscriptAdapters -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeTranscriptAdapters = New-Object System.Collections.ArrayList }'
           Replace = '$script:HordeTranscriptAdapters = New-Object System.Collections.ArrayList' }
    )
}
