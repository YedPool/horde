# Mutations of remote/Overlay.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\overlay.psd1
# Each breaks one rule of remote plan R8; test\test-overlay.ps1 must fail for every one of them.
@{
    Target = "remote\Overlay.ps1"
    Suite  = "test\test-overlay.ps1"
    Mutations = @(
        @{ Name = "host-name-accepted-as-address"
           Find = 'if ($Address -cmatch $p.address) {'
           Replace = 'if ($Address -ne "") {' }
        @{ Name = "overlay-name-unchecked"
           Find = 'if ($name -cnotmatch $p.name) { return'
           Replace = 'if ($name -eq "") { return' }
        @{ Name = "schema-failure-ignored"
           Find = 'if ($found.Count -gt 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "other-overlay-accepted"
           Find = 'if ("$($doc.overlay)" -cne $Name) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "cap-unchecked"
           Find = 'if ($Text.Length -gt $script:HordeOverlayMaxChars) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "non-ascii-accepted"
           Find = 'if ($n -gt 126 -or ($n -lt 32 -and $n -ne 9 -and $n -ne 10 -and $n -ne 13)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "empty-answer-read"
           Find = 'if ($Text.Trim() -eq "") { return (New-HordeUnknown -Reason "the overlay gave no answer") }'
           Replace = '' }
        @{ Name = "peer-matched-ignoring-case"
           Find = 'if ("$($p.name)" -ceq $Peer) {'
           Replace = 'if ("$($p.name)" -eq $Peer) {' }
        @{ Name = "missing-peer-guessed"
           Find = 'return (New-HordeUnknown -Reason ("the overlay lists no peer named '''
           Replace = 'return (New-HordeKnown -Value "$($Endpoint.value.self.address)"); return (New-HordeUnknown -Reason ("the overlay lists no peer named ''' }
        @{ Name = "unknown-endpoint-gives-a-peer"
           Find = 'if ($Endpoint.state -cne "known") { return (New-HordeUnknown -Reason ("the overlay''s answer is unknown: "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the overlay''s answer is unknown: "' }
        @{ Name = "health-note-dropped"
           Find = 'return (New-HordeUnknown -Reason ($why + " (" + $note + ")"))'
           Replace = 'return (New-HordeUnknown -Reason $why)' }
        @{ Name = "healthy-overlay-is-a-link"
           Find = 'if ("$($h.state)" -ceq "known" -and $h.value -is [bool] -and $h.value) { $note = "overlay reports healthy" }'
           Replace = 'if ("$($h.state)" -ceq "known" -and $h.value -is [bool] -and $h.value) { return (New-HordeKnown -Value $true) }' }
        @{ Name = "unhealthy-overlay-takes-the-link-down"
           Find = 'if ("$($Handshake.state)" -ceq "known" -and $Handshake.value -is [bool] -and $Handshake.value) { return (New-HordeKnown -Value $true) }'
           Replace = 'if ("$($Handshake.state)" -ceq "known" -and $Handshake.value -is [bool] -and $Handshake.value -and $Endpoint.value.health.value -ne $false) { return (New-HordeKnown -Value $true) }' }
        @{ Name = "handshake-truthy-is-a-link"
           Find = '-ceq "known" -and $Handshake.value -is [bool] -and $Handshake.value) {'
           Replace = '-ceq "known" -and $Handshake.value -eq $true) {' }
        @{ Name = "address-dollar-anchor"
           Find = 'address = ("$($s.definitions.address.pattern)" -replace ''\$$'', ''\z'')'
           Replace = 'address = "$($s.definitions.address.pattern)"' }
        @{ Name = "name-dollar-anchor"
           Find = 'name = ("$($s.properties.overlay.pattern)" -replace ''\$$'', ''\z'')'
           Replace = 'name = "$($s.properties.overlay.pattern)"' }
        @{ Name = "peer-unchecked"
           Find = 'if ($peer -cnotmatch $p.peer) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "default-peer-dropped"
           Find = '$peer = $script:HordeOverlayDefaultPeer'
           Replace = '$peer = ""' }
        @{ Name = "prefix-any-case"
           Find = 'if ($Address.StartsWith("overlay:", [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($Address.StartsWith("overlay:", [System.StringComparison]::OrdinalIgnoreCase)) {' }
        @{ Name = "absent-health-called-unknown"
           Find = 'elseif ("$($h.state)" -ceq "absent") { $note = "overlay reports no health: " + $h.reason }'
           Replace = '' }
    )
}
