# Mutations of the relay port. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-port.psd1
# Each mutation switches off or loosens one rule of relays/Port.ps1 (relay design 2026-10-09, PR plan
# item 3), and test\test-relay-port.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "relays\Port.ps1"
    Suite  = "test\test-relay-port.ps1"
    Mutations = @(
        # --- registration and capabilities
        @{ Name = "registration-findings-ignored"
           Find = 'if ($findings.Count -gt 0) { throw ("relay '''
           Replace = 'if ($false) { throw ("relay ''' }
        @{ Name = "misnamed-folder-allowed"
           Find = 'if ("$($Capabilities.relay)" -cne $leaf) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-limit-over-ceiling-allowed"
           Find = 'if ($l.maxTextChars -gt $script:HordeRelayTextChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "batch-limit-over-ceiling-allowed"
           Find = 'if ($l.maxBatch -gt $script:HordeRelayBatchMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "watch-limit-over-ceiling-allowed"
           Find = 'if ($l.maxWatchMs -gt $script:HordeRelayWatchMsMax) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-ceiling-drifts-from-envelope"
           Find = '$script:HordeRelayTextChars = 1414507'
           Replace = '$script:HordeRelayTextChars = 1414508' }
        @{ Name = "second-registration-replaces"
           Find = 'if ($script:HordeRelays.ContainsKey("$($caps.relay)")) {'
           Replace = 'if ($false) {' }
        @{ Name = "unverified-counts-as-yes"
           Find = 'return ((Get-HordeRelaySupport -Relay $Relay -Capability $Capability) -ceq "yes")'
           Replace = 'return ((Get-HordeRelaySupport -Relay $Relay -Capability $Capability) -cne "no")' }
        @{ Name = "requirements-ignored"
           Find = 'if (-not (Test-HordeRelayCapability -Relay $Relay -Capability $c)) {'
           Replace = 'if ($false) {' }
        @{ Name = "min-text-ignored"
           Find = 'if ($Relay.limits.maxTextChars -lt $MinTextChars) {'
           Replace = 'if ($false) {' }
        # --- addressing
        @{ Name = "three-part-mailbox-allowed"
           Find = 'if ($parts.Count -ne 2) {'
           Replace = 'if ($parts.Count -lt 2) {' }
        @{ Name = "dot-in-mailbox-allowed"
           Find = '$script:HordeRelaySegmentPattern = ''\A[a-z0-9][a-z0-9-]{0,62}\z'''
           Replace = '$script:HordeRelaySegmentPattern = ''\A[a-z0-9][a-z0-9.-]{0,62}\z''' }
        @{ Name = "mailbox-pattern-ends-before-line-break"
           Find = '$script:HordeRelaySegmentPattern = ''\A[a-z0-9][a-z0-9-]{0,62}\z'''
           Replace = '$script:HordeRelaySegmentPattern = ''^[a-z0-9][a-z0-9-]{0,62}$''' }
        @{ Name = "device-name-allowed"
           Find = 'elseif ($p -cmatch $script:HordeRelayDeviceNamePattern) {'
           Replace = 'elseif ($false) {' }
        # --- a put is checked before the relay sees it
        @{ Name = "line-break-in-text-allowed"
           Find = '$script:HordeRelayTextPattern = ''\A[\x20-\x7E]+\z'''
           Replace = '$script:HordeRelayTextPattern = ''\A[\x09-\x7E]+\z''' }
        @{ Name = "text-cap-off-by-one"
           Find = 'if ($Text.Length -gt $MaxChars) {'
           Replace = 'if ($Text.Length -ge $MaxChars) {' }
        @{ Name = "key-cap-loosened"
           Find = '$script:HordeRelayKeyPattern = ''\A[A-Za-z0-9._:/-]{1,160}\z'''
           Replace = '$script:HordeRelayKeyPattern = ''\A[A-Za-z0-9._:/ -]{1,161}\z''' }
        @{ Name = "no-content-hash-key"
           Find = 'if ($Key -eq "") { $Key = Get-HordeRelayContentKey -Text $Text }'
           Replace = 'if ($Key -eq "") { $Key = "none" }' }
        @{ Name = "look-alike-connection-accepted"
           Find = 'if (-not [object]::ReferenceEquals($script:HordeRelayConnections[$id.Value], $Connection)) { return $false }'
           Replace = '' }
        # --- the relay's answers are checked
        @{ Name = "absent-answer-passed-on"
           Find = 'if ($a.state -ceq "absent") {'
           Replace = 'if ($false) {' }
        @{ Name = "seq-as-text-accepted"
           Find = 'return (($Value -is [int] -or $Value -is [long]) -and $Value -ge 1 -and'
           Replace = 'return ($true -and $Value -ge 1 -and' }
        @{ Name = "seq-zero-accepted"
           Find = '-and $Value -ge 1 -and $Value -le $script:HordeRelaySeqMax)'
           Replace = '-and $Value -ge 0 -and $Value -le $script:HordeRelaySeqMax)' }
        @{ Name = "negative-cursor-accepted"
           Find = '-and $Value -ge 0 -and $Value -le $script:HordeRelaySeqMax)'
           Replace = '-and $Value -ge -1 -and $Value -le $script:HordeRelaySeqMax)' }
        @{ Name = "duplicate-flag-unchecked"
           Find = 'if (-not $dup.has -or $dup.value -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "ack-of-another-cursor-accepted"
           Find = '-or [long]$t.value -ne [long]$Through) {'
           Replace = ') {' }
        @{ Name = "batch-over-limit-asked"
           Find = '-or $Max -gt $Connection.relay.limits.maxBatch) {'
           Replace = ') {' }
        @{ Name = "watch-over-limit-asked"
           Find = '-or $TimeoutMs -gt $most) {'
           Replace = ') {' }
        # --- the items are never believed
        @{ Name = "non-object-item-not-named"
           Find = 'if ($null -eq $it -or -not ($it -is [System.Management.Automation.PSCustomObject] -or $it -is [System.Collections.IDictionary])) {'
           Replace = 'if ($false) {' }
        @{ Name = "item-key-unchecked"
           Find = 'if (-not $key.has -or $key.value -isnot [string] -or $key.value -cnotmatch $script:HordeRelayKeyPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "item-text-unchecked"
           Find = '$tf = Get-HordeRelayTextFinding -Text $text.value -MaxChars $Connection.relay.limits.maxTextChars'
           Replace = '$tf = ""' }
        @{ Name = "stale-item-at-cursor-kept"
           Find = 'if ($s -le $Since) {'
           Replace = 'if ($s -lt $Since) {' }
        @{ Name = "repeat-replaces-first"
           Find = 'if ($bySeq.ContainsKey($s)) {'
           Replace = 'if ($false) {' }
        @{ Name = "excess-items-kept"
           Find = 'if ($ordered.Count -gt $Max) {'
           Replace = 'if ($false) {' }
        @{ Name = "gap-not-reported"
           Find = 'if ($prev -gt 0 -and $it.seq -ne $prev + 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "gap-before-first-ignored"
           Find = '$prev = $Since'
           Replace = '$prev = [long]0' }
        @{ Name = "empty-read-resets-cursor"
           Find = '$next = $Since'
           Replace = '$next = [long]0' }
    )
}
