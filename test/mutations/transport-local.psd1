# Mutations of transports/local/Transport.ps1. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-local.psd1
# transports\local\test\test-local.ps1 must fail for each, except those declared Expect = "survives".
# The native half (the pipe flags, integrity read) is transport-local-native.psd1; the
# transport-neutral behaviour of this file (framing, keepalive) is transport-conformance-local.psd1.
#
# No mutant here is declared to survive. owner-not-checked-on-open is in its own spec,
# transport-local-owner.psd1 (issue #89): the review of PR #42 showed the owner check does not stop a
# low-integrity squatter of the same user - the integrity check that does is
# server-integrity-not-checked-on-open, caught here - and the case that shows the owner refusal end to
# end runs only from a token that may make Administrators an owner.
# PassCodes 0 and 3: test-local passes with 0 from a token that runs the owner case and with 3 from
# one that skips it (review of PR #91, G1); this spec's mutants do not depend on that case.
# image-not-checked-on-open (round 1 survivor) is caught since round 2, by a compiled probe that
# serves the pipe at this process's own level (transports/local/test/SquatProbe.cs).
@{
    Target = "transports\local\Transport.ps1"
    Suite  = "transports\local\test\test-local.ps1"
    PassCodes = @(0, 3)
    Mutations = @(
        @{ Name = "acl-not-protected"
           Find = 'D:P(D;;0x1f019f;;;NU)'
           Replace = 'D:(D;;0x1f019f;;;NU)' }
        @{ Name = "dacl-allow-before-deny"
           Find = '"D:P(D;;0x1f019f;;;NU)(A;;0x1f019f;;;" + $me + ")S:'
           Replace = '"D:P(A;;0x1f019f;;;" + $me + ")(D;;0x1f019f;;;NU)S:' }
        @{ Name = "network-not-denied"
           Find = '(D;;0x1f019f;;;NU)'
           Replace = '' }
        @{ Name = "everyone-allowed"
           Find = 'S:(ML;;NWNR;;;S-1-16-"'
           Replace = '(A;;0x1f019f;;;WD)S:(ML;;NWNR;;;S-1-16-"' }
        @{ Name = "label-without-no-read-up"
           Find = 'S:(ML;;NWNR;;;S-1-16-"'
           Replace = 'S:(ML;;NW;;;S-1-16-"' }
        @{ Name = "label-fixed-at-medium"
           Find = 'S:(ML;;NWNR;;;S-1-16-" + (Get-HordeLocalOwnIntegrity) + ")")'
           Replace = 'S:(ML;;NWNR;;;ME)")' }
        @{ Name = "server-integrity-not-checked-on-open"
           Find = 'if (-not (Test-HordeLocalPeerIntegrity -Peer $sil -Own $own)) {'
           Replace = 'if ($false) {' }
        @{ Name = "client-integrity-not-checked-on-accept"
           Find = 'if (-not (Test-HordeLocalPeerIntegrity -Peer $cil -Own $own)) {'
           Replace = 'if ($false) {' }
        @{ Name = "integrity-compare-loose"
           Find = 'return ($Peer -ge $Own)'
           Replace = 'return $true' }
        @{ Name = "unreadable-integrity-trusted"
           Find = 'if ($Peer -lt 0 -or $Own -lt 0) { return $false }'
           Replace = '' }
        @{ Name = "any-image-accepted"
           Find = 'foreach ($ok in $script:HordeLocalNodeImages) { if ([string]::Equals($Image, $ok, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }'
           Replace = 'return $true' }
        @{ Name = "image-not-checked-on-open"
           Find = 'if (-not (Test-HordeLocalNodeImage -Image $img)) {'
           Replace = 'if ($false) {' }
        @{ Name = "closed-instance-not-replaced"
           Find = '$fresh = New-HordeLocalServer -Pipe $st.pipe'
           Replace = '$fresh = [pscustomobject]@{ stream = $null; reason = "mutant" }' }
        @{ Name = "gap-between-links"
           Find = '$next = New-HordeLocalServer -Pipe $st.pipe'
           Replace = '$next = [pscustomobject]@{ stream = $null; reason = "mutant" }' }
        @{ Name = "owner-compare-always-true"
           Find = 'return ("$Owner" -ceq "$Expected")'
           Replace = 'return $true' }
        @{ Name = "device-id-case-ignored"
           Find = 'if ($DeviceId -cnotmatch $script:HordeLocalIdPattern) { return $null }'
           Replace = 'if ($DeviceId -notmatch $script:HordeLocalIdPattern) { return $null }' }
        @{ Name = "device-id-unchecked"
           Find = 'if ($DeviceId -cnotmatch $script:HordeLocalIdPattern) { return $null }'
           Replace = '' }
        @{ Name = "denied-open-blames-the-acl-alone"
           Find = '" denied the open. Either its ACL does not admit this user, or the node runs at a higher integrity level than this end (this end runs at integrity " + (Get-HordeLocalOwnIntegrity) + "); if it is the real node, run the hub and node at the same integrity level"'
           Replace = '": the ACL does not admit this user"' }
        @{ Name = "acl-refusal-unexplained"
           Find = 'if ($e -is [System.UnauthorizedAccessException]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "accept-peer-unexplained"
           Find = 'how = ("admitted by the pipe''s ACL and label'
           Replace = 'how = ("a peer' }
        @{ Name = "local-refused-flag-dropped"
           Find = '-Ok $false -Refused ($null -ne $st.server) -Reason'
           Replace = '-Ok $false -Reason' }
        @{ Name = "refused-while-the-name-is-free"
           Find = '-Refused ($null -ne $st.server)'
           Replace = '-Refused $true' }
        # --- the hub's own pipe (remote plan R17a) ---
        @{ Name = "hub-endpoint-id-not-checked"
           Find = 'if ($hub -cnotmatch $script:HordeLocalIdPattern) { return $null }'
           Replace = '' }
        @{ Name = "hub-endpoint-prefix-any-case"
           Find = '$DeviceId.StartsWith($script:HordeLocalHubEndpointPrefix, [System.StringComparison]::Ordinal)'
           Replace = '$DeviceId.StartsWith($script:HordeLocalHubEndpointPrefix, [System.StringComparison]::OrdinalIgnoreCase)' }
        @{ Name = "hub-pipe-is-the-node-pipe"
           Find = 'return ($script:HordeLocalHubPipePrefix + $hub)'
           Replace = 'return ($script:HordeLocalPipePrefix + $hub)' }
        @{ Name = "hub-timeout-says-node"
           Find = '{ "hub" } else { "node" }'
           Replace = '{ "node" } else { "node" }' }
        # T-0450: the owner read and its fail-closed refusal, shown without an elevated token by a
        # pipe of the suite's own checked against another expected owner, and by a disposed pipe.
        @{ Name = "owner-of-another-accepted"
           Find = 'if (-not (Test-HordeLocalPipeOwner -Owner $owner -Expected $Expected)) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-owner-accepted"
           Find = 'return ("refused: the owner of " + $Name + " could not be read (" + $e.Message + "); a pipe whose owner cannot be read is not dialled")'
           Replace = 'return ""' }
        @{ Name = "unreadable-owner-called-a-squatter"
           Find = 'return ("refused: the owner of " + $Name + " could not be read (" + $e.Message + "); a pipe whose owner cannot be read is not dialled")'
           Replace = 'return ("refused: " + $Name + " is owned by '''', not by this user; it may be a squatter")' }
        @{ Name = "pwsh-image-dropped"
           Find = '(Join-Path $script:HordeLocalProgramFiles "PowerShell\7\pwsh.exe")'
           Replace = '(Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe")' }
        @{ Name = "pwsh-preview-admitted"
           Find = '(Join-Path $script:HordeLocalProgramFiles "PowerShell\7\pwsh.exe")'
           Replace = '(Join-Path $script:HordeLocalProgramFiles "PowerShell\7\pwsh.exe"), (Join-Path $script:HordeLocalProgramFiles "PowerShell\7-preview\pwsh.exe")' }
        # Not here: a mutant that drops the PipesAclExtensions branch. It changes only pwsh 7, and
        # Mutate runs its suite under 5.1 alone (T-0422), so it would survive for that reason; the
        # check "a dialled pipe's owner is read in this shell" catches it when test-local runs under 7.
    )
}
