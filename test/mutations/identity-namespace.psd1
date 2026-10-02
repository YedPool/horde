# Mutations of core/Identity.ps1's namespace guard (remote plan R11). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\identity-namespace.psd1
# test\test-namespace.ps1 holds the guard with a process table that records every lookup; each
# mutation lets the process check touch the table for a pid that is not this machine's.
@{
    Target = "core\Identity.ps1"
    Suite  = "test\test-namespace.ps1"
    Mutations = @(
        @{ Name = "guard-skipped"
           Find = 'if ($null -ne $Namespace -or $null -ne $Local) {'
           Replace = 'if ($false) {' }
        @{ Name = "remote-pid-looked-up"
           Find = 'if ($placed.value -ne $true) { return [pscustomobject]@{ same = $false; kind = "remote"; reason = $placed.reason } }'
           Replace = '' }
        @{ Name = "remote-pid-called-gone"
           Find = 'kind = "remote"; reason = $placed.reason'
           Replace = 'kind = "gone"; reason = $placed.reason' }
        @{ Name = "namespace-alone-looked-up"
           Find = 'if ($null -ne $Namespace -or $null -ne $Local) {'
           Replace = 'if ($null -ne $Namespace -and $null -ne $Local) {' }
    )
}
