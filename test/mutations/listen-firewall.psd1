# Mutations of horde listen's firewall steps (cli/ListenFirewall.ps1; mesh v1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\listen-firewall.psd1
# test\test-firewall-port.ps1 (a stand-in firewall only) must fail for each.
@{
    Target = "cli\ListenFirewall.ps1"
    Suite  = "test\test-firewall-port.ps1"
    Mutations = @(
        @{ Name = "lan-on-any-port"
           Find = 'if ($Port -lt 1) { $out.reason = "a listener on "'
           Replace = 'if ($false) { $out.reason = "a listener on "' }
        @{ Name = "known-addresses-ignored"
           Find = 'if ($from.Count -eq 0) { $from = @(@($Known)'
           Replace = 'if ($false) { $from = @(@($Known)' }
        @{ Name = "known-added-to-allow-from"
           Find = '$from = @(@($AllowFrom) | Where-Object { "$_".Trim() -ne "" })'
           Replace = '$from = @(@($AllowFrom) + @($Known) | Where-Object { "$_".Trim() -ne "" })' }
        @{ Name = "no-adapter-listens-anyway"
           Find = 'if ($Firewall.state -cne "known") { $out.reason = "the listener on "'
           Replace = 'if ($Firewall.state -cne "known") { $out.ok = $true; return $out; $out.reason = "the listener on "' }
        @{ Name = "no-elevation-command"
           Find = 'Horde never elevates itself. In an elevated PowerShell, run: " + (Get-HordeListenElevationCommand'
           Replace = 'Horde never elevates itself." + (Get-HordeListenElevationCommand' }
        @{ Name = "rule-not-removed"
           Find = '$why = Remove-HordeListenRule -Firewall $Firewall.value -Name $Rule'
           Replace = '$why = ""' }
        @{ Name = "public-network-not-refused"
           Find = 'if ($net.state -ceq "known" -and @(@($spec.value.profiles)'
           Replace = 'if ($false -and @(@($spec.value.profiles)' }
        @{ Name = "unknown-network-refused"
           Find = 'if ($net.state -ceq "known" -and @(@($spec.value.profiles)'
           Replace = 'if ($net.state -cne "known") { $out.reason = "the network could not be read"; return $out }; if ($net.state -ceq "known" -and @(@($spec.value.profiles)' }
        @{ Name = "every-network-refused"
           Find = '-and @(@($spec.value.profiles) | Where-Object { $_ -ceq $net.value }).Count -eq 0) {'
           Replace = ') {' }
        @{ Name = "refused-after-elevation"
           Find = '    $net = Get-HordeListenNetworkProfile -Firewall $fw -Address $Where.address'
           Replace = '    $net = New-HordeUnknown -Reason "later"; if ((@(& $fw.elevated) | Select-Object -Last 1) -eq $true) { $net = Get-HordeListenNetworkProfile -Firewall $fw -Address $Where.address }' }
        @{ Name = "switch-not-given-to-spec"
           Find = '-AllowFrom $from -AllowPublicProfile:$AllowPublicProfile'
           Replace = '-AllowFrom $from' }
        @{ Name = "switch-not-in-elevation-line"
           Find = '-Seconds $Seconds -AllowPublicProfile:$AllowPublicProfile)'
           Replace = '-Seconds $Seconds)' }
        @{ Name = "refusal-drops-the-switch"
           Find = 'Choose one: run horde listen again with -AllowPublicProfile, which'
           Replace = 'Choose one: run horde listen again, which' }
        @{ Name = "refusal-hides-what-private-turns-on"
           Find = 'which also turns on every other inbound rule the system keeps for Private networks'
           Replace = 'which is simple' }
        @{ Name = "said-line-fixed-profiles"
           Find = '(Join-HordeListenProfileWords -Profiles $spec.value.profiles) + " profiles only"'
           Replace = '"Domain and Private profiles only"' }
        @{ Name = "loopback-asks-firewall"
           Find = 'if ($Where.loopback) { $out.ok = $true; $out.said = "loopback needs no firewall rule"; return $out }'
           Replace = '' }
    )
}
