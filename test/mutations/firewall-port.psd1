# Mutations of the firewall port (core/FirewallPort.ps1; mesh v1): one rule of Horde's own, as wide as
# its nodes, idempotent, owned by name, never elevated. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\firewall-port.psd1
# test\test-firewall-port.ps1 (a stand-in firewall only) must fail for each.
@{
    Target = "core\FirewallPort.ps1"
    Suite  = "test\test-firewall-port.ps1"
    Mutations = @(
        @{ Name = "public-profile-allowed"
           Find = '$script:HordeListenRuleProfiles = @("Domain", "Private")'
           Replace = '$script:HordeListenRuleProfiles = @("Domain", "Private", "Public")' }
        @{ Name = "any-local-address"
           Find = 'protocol = "TCP"; localAddress = $k.value.address;'
           Replace = 'protocol = "TCP"; localAddress = "Any";' }
        @{ Name = "loopback-gets-a-rule"
           Find = 'if ($k.value.loopback) { return (New-HordeUnknown -Reason ("''" + $Address + "'' is loopback, which needs no firewall rule")) }'
           Replace = '' }
        @{ Name = "nodes-not-checked"
           Find = 'if ($from.state -cne "known") { return $from }'
           Replace = 'if ($from.state -cne "known") { $from = New-HordeKnown -Value @("Any") }' }
        @{ Name = "foreign-rule-written"
           Find = 'if ("$($Spec.name)".StartsWith($script:HordeListenRulePrefix, [System.StringComparison]::Ordinal) -eq $false) {'
           Replace = 'if ($false) {' }
        @{ Name = "foreign-rule-removed"
           Find = 'if (-not $Name.StartsWith($script:HordeListenRulePrefix, [System.StringComparison]::Ordinal)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "written-without-elevation"
           Find = 'if (-not $elevated) { $out.reason = "changing the firewall needs an administrator'
           Replace = 'if ($false) { $out.reason = "changing the firewall needs an administrator' }
        @{ Name = "always-rewritten"
           Find = 'if (Test-HordeListenRuleSame -Have $have -Want $Spec) {'
           Replace = 'if ($false) {' }
        @{ Name = "profiles-not-compared"
           Find = 'foreach ($f in @("remoteAddresses", "profiles")) {'
           Replace = 'foreach ($f in @("remoteAddresses")) {' }
        @{ Name = "nodes-not-compared"
           Find = 'foreach ($f in @("remoteAddresses", "profiles")) {'
           Replace = 'foreach ($f in @("profiles")) {' }
        @{ Name = "write-not-read-back"
           Find = 'if (-not (Test-HordeListenRuleSame -Have $back -Want $Spec)) {'
           Replace = 'if ($false) {' }
        @{ Name = "remove-not-read-back"
           Find = 'if ($null -ne $left) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "other-system-adapter-used"
           Find = 'if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $a) }'
           Replace = 'return (New-HordeKnown -Value $a)' }
        @{ Name = "elevation-line-drops-allow-from"
           Find = 'if ($from.Count -gt 0) { $line = $line + " -AllowFrom " + ($from -join ",") }'
           Replace = '' }
    )
}
