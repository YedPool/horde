# Mutations of the hub's register of enrolled nodes (cli/HubRegistry.ps1; issue #144 item 3, issue #124).
# Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-registry.psd1
# test\test-hub-registry.ps1 must fail for each.
@{
    Target = "cli\HubRegistry.ps1"
    Suite  = "test\test-hub-registry.ps1"
    Mutations = @(
        # --- the file ---
        @{ Name = "entry-not-made-users-own"
           Find = 'Set-HordeHubRegistryAcl -Path $tmp'
           Replace = '$null = $tmp' }
        @{ Name = "entry-written-unchecked"
           Find = 'if ($found.Count -gt 0) { throw ("this register entry is not one to write: "'
           Replace = 'if ($false) { throw ("this register entry is not one to write: "' }
        @{ Name = "entry-named-by-anything"
           Find = 'if ($DeviceId -cnotmatch $script:HordeHubRegistryDevicePattern) { throw'
           Replace = 'if ($false) { throw' }
        # --- reading it ---
        @{ Name = "entry-read-unchecked"
           Find = 'if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("the register entry " + $path + " is not one to trust: "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the register entry " + $path + " is not one to trust: "' }
        @{ Name = "entry-of-another-device-believed"
           Find = 'if ("$($e.deviceId)" -cne $DeviceId) { return'
           Replace = 'if ($false) { return' }
        # --- live ---
        @{ Name = "revoked-entry-live"
           Find = 'if ($null -ne $e.PSObject.Properties["revokedAt"]) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "expiry-ignored"
           Find = 'if (Test-HordeHubExpired -Expires "$($e.expires)" -Now $Now) {'
           Replace = 'if ($false) {' }
        @{ Name = "expiry-day-still-live"
           Find = 'return ($Now.ToLocalTime().Date -ge $d.Date)'
           Replace = 'return ($Now.ToLocalTime().Date -gt $d.Date)' }
        # Caught where local time is behind UTC (the boundary case's local midnight is then the next UTC
        # day); on a machine set to UTC the two readings are the same.
        @{ Name = "expiry-read-in-utc"
           Find = 'return ($Now.ToLocalTime().Date -ge $d.Date)'
           Replace = 'return ($Now.ToUniversalTime().Date -ge $d.Date)' }
        @{ Name = "bad-expiry-never-ends"
           Find = '[ref]$d)) { return $true }'
           Replace = '[ref]$d)) { return $false }' }
        # --- revoking ---
        @{ Name = "revoke-not-written"
           Find = '$null = Write-HordeHubEnrolment -HordeHome $HordeHome -Entry $e'
           Replace = '$null = $e' }
        @{ Name = "revoke-of-unreadable-entry-silent"
           Find = 'if ($r.state -cne "known") { return ("the hub''s register entry for device "'
           Replace = 'if ($r.state -cne "known") { return ""; return ("the hub''s register entry for device "' }
        # --- admission: both records must agree ---
        @{ Name = "register-not-asked"
           Find = 'if ($k.state -cne "known") { return ("device " + $DeviceId + " is not enrolled: " + $k.reason) }'
           Replace = '' }
        @{ Name = "transport-not-asked"
           Find = 'if ($null -eq $t -or -not $t.ok) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "keys-not-compared"
           Find = 'if ("$($t.line)" -cne "$($k.value)") {'
           Replace = 'if ($false) {' }
        @{ Name = "transport-throw-admits"
           Find = 'try { $t = & $Enrollment.hubEnrolled $HordeHome $DeviceId $Now } catch { return ('
           Replace = 'try { $t = & $Enrollment.hubEnrolled $HordeHome $DeviceId $Now } catch { return ""; return (' }
    )
}
