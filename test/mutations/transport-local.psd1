# Mutations of transports/local/Transport.ps1. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-local.psd1
# transports\local\test\test-local.ps1 must fail for each, except those declared Expect = "survives".
# The transport-neutral behaviour of the same file (framing, keepalive) is mutated in
# transport-conformance.psd1, against the conformance suite.
@{
    Target = "transports\local\Transport.ps1"
    Suite  = "transports\local\test\test-local.ps1"
    Mutations = @(
        @{ Name = "acl-inherits"
           Find = '$sec.SetAccessRuleProtection($true, $false)'
           Replace = '$sec.SetAccessRuleProtection($false, $true)' }
        @{ Name = "network-not-denied"
           Find = '$sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($net,'
           Replace = '$null = ((New-Object System.IO.Pipes.PipeAccessRule($net,' }
        @{ Name = "everyone-allowed"
           Find = '$sec.SetOwner($me)'
           Replace = '$sec.SetOwner($me); $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule((New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)), [System.IO.Pipes.PipeAccessRights]::ReadWrite, [System.Security.AccessControl.AccessControlType]::Allow)))' }
        @{ Name = "owner-compare-always-true"
           Find = 'return ("$Owner" -ceq "$Expected")'
           Replace = 'return $true' }
        @{ Name = "owner-not-checked-on-open"
           Find = 'if (-not (Test-HordeLocalPipeOwner -Owner $owner -Expected $me)) {'
           Replace = 'if ($false) {'
           Expect = "survives"
           Reason = "Only a pipe owned by another user reaches this line, and making one needs a second account, which the machine this was written on does not have. Test-HordeLocalPipeOwner itself is tested, and owner-compare-always-true is caught." }
        @{ Name = "device-id-case-ignored"
           Find = 'if ($DeviceId -cnotmatch $script:HordeLocalIdPattern) { return $null }'
           Replace = 'if ($DeviceId -notmatch $script:HordeLocalIdPattern) { return $null }' }
        @{ Name = "device-id-unchecked"
           Find = 'if ($DeviceId -cnotmatch $script:HordeLocalIdPattern) { return $null }'
           Replace = '' }
        @{ Name = "two-instances"
           Find = '$state.server = New-Object System.IO.Pipes.NamedPipeServerStream($pipe, [System.IO.Pipes.PipeDirection]::InOut, 1,'
           Replace = '$state.server = New-Object System.IO.Pipes.NamedPipeServerStream($pipe, [System.IO.Pipes.PipeDirection]::InOut, 2,' }
        @{ Name = "acl-refusal-unexplained"
           Find = 'if ($e -is [System.UnauthorizedAccessException]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "accept-peer-unexplained"
           Find = 'how = "admitted by the pipe''s ACL: this user only, no network logons"'
           Replace = 'how = "a peer"' }
    )
}
