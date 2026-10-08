# Mutations of core/FleetWorkStore.ps1, the append writer of the fleet-work record. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-work-store.psd1
# Each breaks one thing the writer promises - only what reads is written, only with consent, one whole
# line, once, at the end, by one writer at a time - and test\test-fleet-work.ps1 must fail a check for
# every one.
#
# NOT HERE: that the bytes reach the disk (write-through and the flush). No test here can cut the power.
# Nor the gate's own rules: they are core/MetricsStore.ps1's, held by test\mutations\metrics-store.psd1.
@{
    Target = "core\FleetWorkStore.ps1"
    Suite  = "test\test-fleet-work.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "refused-is-written"
           Find = '    if ($read.state -cne "read") { return'
           Replace = '    if ($false) { return' }
        @{ Name = "consent-ignored"
           Find = '    if (-not $consent.write) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "before-consent-not-said"
           Find = '-and $Time -lt $gate.value.enabledAt) {'
           Replace = '-and $false) {' }
        @{ Name = "folder-made-before-consent"
           Find = '    $consent = Get-HordeFleetWorkConsent -Time'
           Replace = '    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName((Get-HordeFleetWorkLogPath))); $consent = Get-HordeFleetWorkConsent -Time' }
        @{ Name = "no-dedupe"
           Find = '        if ($null -ne $kept) {'
           Replace = '        if ($false) {' }
        @{ Name = "differs-not-said"
           Find = '            if ($kept -cne $line) {'
           Replace = '            if ($false) {' }
        @{ Name = "broken-line-keeps-id"
           Find = '        if ($a.state -ceq "read" -and $a.event.id -ceq $Id) { return $lineText }'
           Replace = '        return $lineText' }
        @{ Name = "unended-line-keeps-id"
           Find = '    for ($n = 0; $n -lt $parts.Length - 1; $n++) {'
           Replace = '    for ($n = 0; $n -lt $parts.Length; $n++) {' }
        @{ Name = "no-line-break-after-torn"
           Find = '        if ($got -gt 0 -and $have[$got - 1] -ne 10) { $lead = "`n" }'
           Replace = '' }
        @{ Name = "written-at-the-start"
           Find = '        [void]$fs.Seek(0, [System.IO.SeekOrigin]::End)'
           Replace = '        [void]$fs.Seek(0, [System.IO.SeekOrigin]::Begin)' }
        @{ Name = "no-escape-of-wide-characters"
           Find = "    return [regex]::Replace(`$json, '[^\x00-\x7F]',"
           Replace = "    return `$json; [regex]::Replace(`$json, '[^\x00-\x7F]'," }
        @{ Name = "shared-for-writing"
           Find = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read, 4096'
           Replace = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite, 4096' }
        @{ Name = "busy-without-waiting"
           Find = '            if ($clock.ElapsedMilliseconds -ge $WaitMs) { return $null }'
           Replace = '            return $null' }
        @{ Name = "any-failure-is-busy"
           Find = '            if ($ex -isnot [System.IO.IOException] -or ($code -ne 32 -and $code -ne 33)) { throw }'
           Replace = '' }
    )
}
