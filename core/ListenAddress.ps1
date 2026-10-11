# core/ListenAddress - which addresses the hub may listen on, and which it may let nodes reach it from.
#
# THE RULE (mesh v1, the founder's non-negotiable rule 4 of 2026-10-11): THE HUB NEVER LISTENS ON A
# PUBLIC ADDRESS. It listens on whichever private network the founder picks - the office LAN, Tailscale,
# WireGuard - and on nothing else, so no overlay is required and none is locked in. An address is taken
# only when it is one of:
#   127.0.0.0/8, ::1          loopback, the default
#   10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16    RFC 1918 private (an office or home LAN)
#   100.64.0.0/10             RFC 6598 shared address space (CGNAT; Tailscale's addresses)
#   169.254.0.0/16, fe80::/10 link-local
#   fc00::/7                  IPv6 unique local (ULA; WireGuard and Tailscale's IPv6)
# and it is refused, with the reason, when it is anything else: a public address above all, but also
# 0.0.0.0 and :: (every interface, a public one included), a multicast or broadcast address, an
# IPv4-mapped IPv6 form (write the IPv4 address), or a name (a name can resolve to anything).
# THE ADDRESS MUST BE THIS MACHINE'S: one an interface that is up holds now, so a typo or a network
# that went away is said before anything listens.
#
# PURE, apart from Get-HordeLocalAddresses, which reads this machine's interfaces and nothing else.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Tristate.ps1")

# Each private range as { family; bytes; bits; name }: the address's first -bits bits must equal those of
# -bytes. In the order the header lists them.
$script:HordeListenRanges = @(
    [pscustomobject]@{ family = "v4"; bytes = @(127, 0, 0, 0); bits = 8; name = "loopback" },
    [pscustomobject]@{ family = "v4"; bytes = @(10, 0, 0, 0); bits = 8; name = "private (RFC 1918)" },
    [pscustomobject]@{ family = "v4"; bytes = @(172, 16, 0, 0); bits = 12; name = "private (RFC 1918)" },
    [pscustomobject]@{ family = "v4"; bytes = @(192, 168, 0, 0); bits = 16; name = "private (RFC 1918)" },
    [pscustomobject]@{ family = "v4"; bytes = @(100, 64, 0, 0); bits = 10; name = "shared address space (CGNAT, Tailscale)" },
    [pscustomobject]@{ family = "v4"; bytes = @(169, 254, 0, 0); bits = 16; name = "link-local" },
    [pscustomobject]@{ family = "v6"; bytes = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1); bits = 128; name = "loopback" },
    [pscustomobject]@{ family = "v6"; bytes = @(0xfc, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); bits = 7; name = "unique local (ULA)" },
    [pscustomobject]@{ family = "v6"; bytes = @(0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0); bits = 10; name = "link-local" }
)

function Test-HordeAddressInRange {
    # Do the first -Bits bits of -Bytes equal those of -Prefix? Never for an address of another family.
    param([byte[]]$Bytes, [object[]]$Prefix, [int]$Bits)
    if ($Bytes.Length -ne $Prefix.Count) { return $false }
    for ($i = 0; $i -lt $Bits; $i++) {
        $byte = [int][Math]::Floor($i / 8)
        $mask = 0x80 -shr ($i % 8)
        if (($Bytes[$byte] -band $mask) -ne ([int]$Prefix[$byte] -band $mask)) { return $false }
    }
    return $true
}

function Get-HordeListenAddressKind {
    # What kind of address -Address is, as an answer: known { address (the canonical text); family
    # ("v4" or "v6"); kind (the range's name); loopback ($true or $false) } when the hub may listen on
    # it, or unknown with the reason when it may not (header).
    param([AllowEmptyString()][string]$Address)
    $text = "$Address".Trim()
    if ($text -eq "") { return (New-HordeUnknown -Reason "no address was given") }
    # Text that is not an address, a name above all, is refused: IPAddress.TryParse would also take
    # "1" or "0x7f.1" as an address, so the text must be the address's own canonical form, or dotted
    # IPv4 with four parts.
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($text, [ref]$ip)) { return (New-HordeUnknown -Reason ("'" + $text + "' is not an IP address; a name is never taken, since it could resolve to a public address")) }
    $v4 = ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork)
    if ($v4 -and $text -cnotmatch '\A(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}\z') { return (New-HordeUnknown -Reason ("'" + $text + "' is not an IPv4 address written as four decimal numbers")) }
    if ($ip.Equals([System.Net.IPAddress]::Any) -or $ip.Equals([System.Net.IPAddress]::IPv6Any)) { return (New-HordeUnknown -Reason ("'" + $text + "' means every interface, a public one included; the hub never listens on a public address, so name the one private address it should listen on")) }
    if (-not $v4 -and $ip.IsIPv4MappedToIPv6) { return (New-HordeUnknown -Reason ("'" + $text + "' is an IPv4 address in IPv6 form; write the IPv4 address itself")) }
    $family = "v6"; if ($v4) { $family = "v4" }
    $bytes = $ip.GetAddressBytes()
    # An IPv4 address is never held to an IPv6 range, nor the other way: Test-HordeAddressInRange refuses
    # prefixes of another length (252.0.0.1 would otherwise match fc00::/7).
    foreach ($r in $script:HordeListenRanges) {
        if (Test-HordeAddressInRange -Bytes $bytes -Prefix $r.bytes -Bits $r.bits) {
            return (New-HordeKnown -Value ([pscustomobject]@{ address = $ip.ToString(); family = $family; kind = $r.name; loopback = [bool]($r.name -ceq "loopback") }))
        }
    }
    return (New-HordeUnknown -Reason ("'" + $text + "' is a public address (not loopback, private, CGNAT, link-local or unique local), and the hub never listens on a public address: name an address of the private network the nodes reach it on"))
}

function Get-HordeLocalAddresses {
    # Every address an interface of this machine that is up holds now, as canonical text.
    $out = New-Object System.Collections.ArrayList
    foreach ($n in @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces())) {
        if ($n.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        foreach ($u in @($n.GetIPProperties().UnicastAddresses)) { [void]$out.Add($u.Address.ToString()) }
    }
    return @($out)
}

function Resolve-HordeListenAddress {
    # The address the hub may listen on, as an answer: Get-HordeListenAddressKind's, and only when one of
    # -LocalAddresses (this machine's, Get-HordeLocalAddresses, by default) is that address. A loopback
    # address is always this machine's.
    param([AllowEmptyString()][string]$Address, [string[]]$LocalAddresses = $null)
    $k = Get-HordeListenAddressKind -Address $Address
    if ($k.state -cne "known") { return $k }
    if ($k.value.loopback) { return $k }
    if ($null -eq $LocalAddresses) { $LocalAddresses = @(Get-HordeLocalAddresses) }
    foreach ($l in @($LocalAddresses)) {
        $ip = $null
        if ([System.Net.IPAddress]::TryParse("$l", [ref]$ip) -and $ip.ToString() -ceq $k.value.address) { return $k }
    }
    return (New-HordeUnknown -Reason ("'" + $k.value.address + "' is " + $k.value.kind + ", but no interface of this machine that is up holds it now: check the address, or bring that network up"))
}

function Resolve-HordeAllowFrom {
    # The addresses a node may reach the hub from, checked: known, the list in canonical text, sorted,
    # each once; unknown with the reason when the list is empty or any entry is not a single private
    # address of the kinds the hub may listen on (a public address, a range, a name or "any" is never
    # let in). A loopback address is refused too: a node on this machine needs no firewall rule.
    param([string[]]$Addresses)
    $list = @(@($Addresses) | Where-Object { "$_".Trim() -ne "" } | ForEach-Object { ("" + $_).Split(",") } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($list.Count -eq 0) { return (New-HordeUnknown -Reason "no address to let nodes in from: name each node's address with -AllowFrom, or enrol each node with horde hub enroll -Address") }
    $out = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($a in $list) {
        $k = Get-HordeListenAddressKind -Address $a
        if ($k.state -cne "known") { return (New-HordeUnknown -Reason ("a node's address " + $k.reason)) }
        if ($k.value.loopback) { return (New-HordeUnknown -Reason ("'" + $a + "' is loopback; a node on this machine needs no rule, and the hub lets in only other machines' addresses")) }
        [void]$out.Add($k.value.address)
    }
    return (New-HordeKnown -Value @($out))
}
