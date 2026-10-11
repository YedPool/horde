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
        # --- the live register the listener is handed ---
        @{ Name = "live-keys-include-dead-entries"
           Find = 'if ($k.state -ceq "known") { $out[$id] = $k.value }'
           Replace = '$out[$id] = "" + $k.value' }
        # --- mesh v1: a node's last-known address ---
        @{ Name = "node-address-unchecked"
           Find = 'if ($from.state -cne "known" -or @($from.value).Count -ne 1) { throw ("the node''s address: "'
           Replace = 'if ($false) { throw ("the node''s address: "' }
        @{ Name = "node-address-lost-on-renewal"
           Find = 'if ($old.state -ceq "known" -and $null -ne $old.value.PSObject.Properties["address"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "revoked-node-address-let-in"
           Find = 'foreach ($id in @((Get-HordeHubLiveKeys -HordeHome $HordeHome -Now $Now).Keys)) {'
           Replace = 'foreach ($id in @(Get-ChildItem -LiteralPath (Get-HordeHubRegistryRoot -HordeHome $HordeHome) -Filter "*-*-*-*-*.json" | ForEach-Object { $_.BaseName })) {' }
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
        # --- the first live mesh link (2026-10-11): the nodes horde nodes lists
        @{ Name = "listed-skips-register"
           Find = 'foreach ($id in @((Get-HordeHubLiveKeys -HordeHome $HordeHome -Now $Now).Keys | Sort-Object)) {'
           Replace = 'foreach ($id in @()) {' }
        @{ Name = "listed-twice"
           Find = 'if ($seen.ContainsKey("$id")) { continue }'
           Replace = '' }
        @{ Name = "listed-own-dropped"
           Find = 'foreach ($e in @($Own | Where-Object { $null -ne $_ })) { [void]$out.Add($e); $seen["$($e.deviceId)"] = $true }'
           Replace = '' }
    )
}
