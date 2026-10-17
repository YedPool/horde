# Mutations of the notice services (notices/Services.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\notice-services.psd1
# test\test-notice-services.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "notices\Services.ps1"
    Suite  = "test\test-notice-services.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "anyone-may-register"
           Find = 'if ($allowed -cnotcontains "$($Registrar.label)" -or -not (Test-HordeRegistrarLabel -Registrar $Registrar)) { return (& $no ("no service was registered'
           Replace = 'if ($false) { return (& $no ("no service was registered' }
        @{ Name = "anyone-may-revoke"
           Find = 'if ($allowed -cnotcontains "$($Registrar.label)" -or -not (Test-HordeRegistrarLabel -Registrar $Registrar)) { return (& $no ("no service was revoked'
           Replace = 'if ($false) { return (& $no ("no service was revoked' }
        @{ Name = "reserved-words-are-allowed"
           Find = 'if ($script:HordeServiceReservedWords -contains $bare -or $bare -match ''\A(orc|thrall|founder|horde)'') {'
           Replace = 'if ($false) {' }
        @{ Name = "orc-shaped-names-are-allowed"
           Find = 'if ($bare -match ''\A[a-z][a-z0-9]{0,3}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "fleet-labels-are-allowed"
           Find = 'if ((Get-HordeServiceBare -Text "$l") -ceq $bare) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-name-that-became-a-label-still-sends"
           Find = 'if ($bad -cne "") { return (& $no ("no notice was sent: " + $bad)) }'
           Replace = '' }
        @{ Name = "a-wrong-secret-is-accepted"
           Find = 'if (-not (Test-HordeConstantTimeEqual -A (ConvertTo-HordeServiceHash -Salt $rec.salt -Secret $secret) -B $rec.hash)) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-open-secret-file-is-accepted"
           Find = 'if ($open -cne "") { return (& $no ("no notice was sent: " + $open)) }'
           Replace = '' }
        @{ Name = "the-secret-file-is-created-with-inherited-access"
           Find = '    $sec = New-HordeSecretFileSecurity'
           Replace = '    $sec = $null' }
        @{ Name = "a-file-of-another-owner-is-accepted"
           Find = 'if (-not (Test-HordeSecretFileOwner -Owner $owner -Mine $mine -Elevated $admin)) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-administrators-owner-is-allowed-without-elevation"
           Find = 'return ($Owner -ceq $Mine -or ($Elevated -and $Owner -ceq "S-1-5-32-544"))'
           Replace = 'return ($Owner -ceq $Mine -or $Owner -ceq "S-1-5-32-544")' }
        @{ Name = "the-seam-replaces-the-real-guard"
           Find = '$repos = @((Split-Path -Parent $PSScriptRoot))'
           Replace = '$repos = @()' }
        @{ Name = "writing-the-permissions-is-allowed"
           Find = '([int]$r.FileSystemRights -band 0x40000) -ne 0 -or ([int]$r.FileSystemRights -band 0x80000) -ne 0 -or'
           Replace = '' }
        @{ Name = "a-name-already-registered-is-registered-again"
           Find = 'if ($cur.value.ContainsKey($Name)) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-secret-looking-name-is-allowed"
           Find = 'if ((Find-HordeSecretKind -Text (Get-HordeServiceLabel -Name $Name)) -cne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "any-other-reader-is-allowed"
           Find = 'if ($allowed -ccontains $sid) { continue }'
           Replace = 'continue' }
        @{ Name = "the-agent-name-proves-a-registrar"
           Find = 'return ($null -ne $p -and "$($p.Value)" -ceq "registry")'
           Replace = 'return $true' }
        @{ Name = "a-secret-file-in-the-repository-is-allowed"
           Find = 'if ($inside.Count -gt 0) {'
           Replace = 'if ($false) {' }
    )
}
