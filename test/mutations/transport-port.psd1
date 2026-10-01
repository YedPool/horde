# Mutations of transports/Port.ps1, the transport port. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-port.psd1
# Each breaks one rule the port exists for; test\test-transport-port.ps1, which drives the port over a
# scripted byte channel, must fail for every one.
@{
    Target = "transports\Port.ps1"
    Suite  = "test\test-transport-port.ps1"
    Mutations = @(
        @{ Name = "partial-frame-delivered"
           Find = 'if ($n -gt 0) { return (New-HordeUnknown -Reason ("a partial frame of "'
           Replace = 'if ($n -gt 0) { return (New-HordeKnown -Value "partial"); return (New-HordeUnknown -Reason ("a partial frame of "' }
        @{ Name = "closed-link-is-absent"
           Find = 'return (New-HordeUnknown -Reason ("the link is closed (" + $Link.closedReason + "); no frame"))'
           Replace = 'return (New-HordeAbsent -Note "closed")' }
        @{ Name = "eof-not-closing"
           Find = '"eof"   { Set-HordeLinkClosed -Link $Link -Reason "the far end closed the link"; return $false }'
           Replace = '"eof"   { return $false }' }
        @{ Name = "read-error-not-closing"
           Find = '"error" { Set-HordeLinkClosed -Link $Link -Reason ("the link failed while reading: " + $r.reason); return $false }'
           Replace = '"error" { return $false }' }
        @{ Name = "receive-cap-off-by-one"
           Find = 'if ($lf -gt $Link.maxFrameBytes -or'
           Replace = 'if ($lf -gt $Link.maxFrameBytes + 1 -or' }
        @{ Name = "overflow-without-lf-waits"
           Find = '($lf -lt 0 -and $Link.buffer.Count -gt $Link.maxFrameBytes)'
           Replace = '($false)' }
        @{ Name = "receive-not-ascii-accepted"
           Find = 'try { $text = $script:HordeLinkAscii.GetString($bytes) }'
           Replace = 'try { $text = [System.Text.Encoding]::UTF8.GetString($bytes) }' }
        @{ Name = "send-lf-allowed"
           Find = 'if ($Frame.IndexOf([char]10) -ge 0) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "send-cap-off-by-one"
           Find = 'if ($bytes.Length -gt $Link.maxFrameBytes) { throw'
           Replace = 'if ($bytes.Length -gt $Link.maxFrameBytes + 1) { throw' }
        @{ Name = "send-ascii-lossy"
           Find = 'try { $bytes = $script:HordeLinkAscii.GetBytes($Frame) }'
           Replace = 'try { $bytes = [System.Text.Encoding]::ASCII.GetBytes($Frame) }' }
        @{ Name = "send-not-a-string"
           Find = 'if ($Frame -isnot [string]) { throw "refused: a frame is a string" }'
           Replace = '$Frame = "" + $Frame' }
        @{ Name = "broken-write-reported-sent"
           Find = 'return (New-HordeUnknown -Reason ("the link broke while sending; whether the far end received any of the frame is unknown ("'
           Replace = 'return (New-HordeKnown -Value "sent"); return (New-HordeUnknown -Reason ("the link broke while sending; whether the far end received any of the frame is unknown ("' }
        @{ Name = "send-on-closed-link"
           Find = 'if ($Link.closed) { return (New-HordeUnknown -Reason ("the link is closed (" + $Link.closedReason + "); nothing was sent")) }'
           Replace = '' }
        @{ Name = "write-timeout-ignored"
           Find = 'if (-not $task.Wait($TimeoutMs)) {'
           Replace = 'if ($false) {' }
        @{ Name = "pending-write-overtaken"
           Find = 'if ($null -ne $Link.pendingWrite) {'
           Replace = 'if ($false) {' }
        @{ Name = "health-open-without-keepalive"
           Find = 'if ($Link.keepalive) { return (New-HordeKnown'
           Replace = 'if ($true) { return (New-HordeKnown' }
        @{ Name = "health-does-not-drain"
           Find = 'for ($i = 0; $i -lt 64; $i++)'
           Replace = 'for ($i = 0; $i -lt 1; $i++)' }
        @{ Name = "close-twice-closes-twice"
           Find = 'if ($Link.closed) { return }'
           Replace = '' }
        @{ Name = "unverified-counts-as-yes"
           Find = 'return ((Get-HordeTransportSupport -Transport $Transport -Capability $Capability) -ceq "yes")'
           Replace = 'return ((Get-HordeTransportSupport -Transport $Transport -Capability $Capability) -cne "no")' }
        @{ Name = "link-path-requires-nothing"
           Find = '$script:HordeLinkRequires = @("auth.peer")'
           Replace = '$script:HordeLinkRequires = @()' }
        @{ Name = "hub-dials-on-dial-out"
           Find = 'if ($Role -eq "hub") { $need = "dial.in" }'
           Replace = '' }
        @{ Name = "folder-name-not-checked"
           Find = 'if ("$($Capabilities.transport)" -cne $leaf) {'
           Replace = 'if ($false) {' }
        @{ Name = "second-registration-replaces"
           Find = 'if ($script:HordeTransports.ContainsKey("$($caps.transport)")) {'
           Replace = 'if ($false) {' }
        @{ Name = "schema-not-checked"
           Find = '$findings = @(Test-HordeSchema -Value $Capabilities -Schema $schema)'
           Replace = '$findings = @()' }
        @{ Name = "adapter-throw-escapes"
           Find = 'catch { return [pscustomobject]@{ ok = $false; channel = $null; peer = $null; listener = $null; reason = ($What + " failed: " + $_.Exception.Message) } }'
           Replace = 'catch { throw }' }
        @{ Name = "probe-bare-value-believed"
           Find = 'if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "missing-peer-trusted"
           Find = '$peerRec = [pscustomobject]@{ verified = $false; identity = ""; how = "the transport reported no peer" }'
           Replace = '$peerRec = [pscustomobject]@{ verified = $true; identity = "?"; how = "assumed" }' }
    )
}
