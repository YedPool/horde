# Mutations of which addresses the hub may listen on and let nodes in from (core/ListenAddress.ps1; mesh
# v1, the founder's rule 4: the hub never listens on a public address). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\listen-address.psd1
# test\test-listen-address.ps1 must fail for each.
@{
    Target = "core\ListenAddress.ps1"
    Suite  = "test\test-listen-address.ps1"
    Mutations = @(
        @{ Name = "public-address-taken"
           Find = 'return (New-HordeUnknown -Reason ("''" + $text + "'' is a public address'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ address = $ip.ToString(); family = $family; kind = "public"; loopback = $false })); return (New-HordeUnknown -Reason ("''" + $text + "'' is a public address' }
        @{ Name = "every-interface-taken"
           Find = 'if ($ip.Equals([System.Net.IPAddress]::Any) -or $ip.Equals([System.Net.IPAddress]::IPv6Any)) {'
           Replace = 'if ($false) {' }
        @{ Name = "rfc1918-172-too-wide"
           Find = 'bytes = @(172, 16, 0, 0); bits = 12;'
           Replace = 'bytes = @(172, 16, 0, 0); bits = 11;' }
        @{ Name = "cgnat-too-wide"
           Find = 'bytes = @(100, 64, 0, 0); bits = 10;'
           Replace = 'bytes = @(100, 64, 0, 0); bits = 9;' }
        @{ Name = "ula-too-wide"
           Find = 'bytes = @(0xfc, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); bits = 7;'
           Replace = 'bytes = @(0xfc, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); bits = 6;' }
        @{ Name = "link-local-v6-too-wide"
           Find = 'bytes = @(0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); bits = 10;'
           Replace = 'bytes = @(0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); bits = 9;' }
        @{ Name = "range-compares-whole-bytes"
           Find = '$mask = 0x80 -shr ($i % 8)'
           Replace = '$mask = 0xff' }
        @{ Name = "mapped-v6-taken"
           Find = 'if (-not $v4 -and $ip.IsIPv4MappedToIPv6) {'
           Replace = 'if ($false) {' }
        @{ Name = "short-ipv4-forms-taken"
           Find = 'if ($v4 -and $text -cnotmatch'
           Replace = 'if ($false -and $text -cnotmatch' }
        @{ Name = "family-ignored"
           Find = 'if ($r.family -cne $family) { continue }'
           Replace = '' }
        @{ Name = "not-this-machines-taken"
           Find = 'return (New-HordeUnknown -Reason ("''" + $k.value.address + "'' is " + $k.value.kind + ", but no interface'
           Replace = 'return $k; return (New-HordeUnknown -Reason ("''" + $k.value.address + "'' is " + $k.value.kind + ", but no interface' }
        @{ Name = "public-held-address-taken"
           Find = '    if ($k.state -cne "known") { return $k }'
           Replace = '' }
        @{ Name = "loopback-let-in"
           Find = 'if ($k.value.loopback) { return (New-HordeUnknown -Reason ("''" + $a + "'' is loopback'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("''" + $a + "'' is loopback' }
        @{ Name = "empty-allow-list-is-any"
           Find = 'if ($list.Count -eq 0) { return (New-HordeUnknown -Reason "no address to let nodes in from'
           Replace = 'if ($list.Count -eq 0) { return (New-HordeKnown -Value @("0.0.0.0")); return (New-HordeUnknown -Reason "no address to let nodes in from' }
        @{ Name = "bad-node-address-skipped"
           Find = 'if ($k.state -cne "known") { return (New-HordeUnknown -Reason ("a node''s address " + $k.reason)) }'
           Replace = 'if ($k.state -cne "known") { continue }' }
        @{ Name = "allow-list-not-split"
           Find = 'ForEach-Object { ("" + $_).Split(",") } |'
           Replace = '' }
    )
}
