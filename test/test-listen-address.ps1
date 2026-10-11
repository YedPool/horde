# WHICH ADDRESSES MAY THE HUB LISTEN ON, AND LET NODES IN FROM? NEVER A PUBLIC ONE.
#
# Mesh v1, the founder's non-negotiable rule 4 (2026-10-11): the hub never listens on a public address.
# core/ListenAddress.ps1 is the rule, pure but for reading this machine's interfaces: loopback, RFC 1918,
# CGNAT 100.64.0.0/10, link-local and IPv6 unique local are taken; a public address, every interface
# (0.0.0.0, ::), multicast and broadcast, an IPv4-mapped IPv6 form and any name are refused, each with
# the reason; and the address must be one this machine holds. The same rule decides who a firewall rule
# may let in. Then `horde listen`, run as a user would, refuses each before anything listens.
# Every case attacks the boundary of a range from both sides.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
. (Join-Path $root "core\ListenAddress.ps1")

function Kind { param([string]$A) return (Get-HordeListenAddressKind -Address $A) }

Write-Host ""
Write-Host "--- taken: loopback and the private ranges, each at both ends ---" -ForegroundColor Cyan
$taken = [ordered]@{
    "127.0.0.1" = "loopback"; "127.255.255.254" = "loopback"; "::1" = "loopback"
    "10.0.0.0" = "private (RFC 1918)"; "10.255.255.255" = "private (RFC 1918)"
    "172.16.0.0" = "private (RFC 1918)"; "172.31.255.255" = "private (RFC 1918)"
    "192.168.0.0" = "private (RFC 1918)"; "192.168.1.182" = "private (RFC 1918)"; "192.168.255.255" = "private (RFC 1918)"
    "100.64.0.0" = "shared address space (CGNAT, Tailscale)"; "100.127.255.255" = "shared address space (CGNAT, Tailscale)"
    "169.254.0.1" = "link-local"; "fe80::1" = "link-local"; "febf::1" = "link-local"
    "fc00::1" = "unique local (ULA)"; "fd7a:115c:a1e0::1" = "unique local (ULA)"; "fdff:ffff::1" = "unique local (ULA)"
}
foreach ($a in $taken.Keys) {
    $k = Kind $a
    Check ($k.state -ceq "known" -and $k.value.kind -ceq $taken[$a]) ("'" + $a + "' is taken, as " + $taken[$a] + " (" + $k.state + " " + $k.reason + ")")
}
$k = Kind "  192.168.1.182 "
Check ($k.state -ceq "known" -and $k.value.address -ceq "192.168.1.182" -and $k.value.family -ceq "v4" -and -not $k.value.loopback) "spaces around it are trimmed, and the answer carries the canonical address, its family and that it is not loopback"
$k = Kind "FD00:0000::0001"
Check ($k.state -ceq "known" -and $k.value.address -ceq "fd00::1" -and $k.value.family -ceq "v6") ("an IPv6 address comes back canonical (" + $k.value.address + ")")
Check ((Kind "127.0.0.1").value.loopback -and (Kind "::1").value.loopback) "loopback says so"

Write-Host ""
Write-Host "--- refused: public, every interface, special, mapped, and anything that is not an address ---" -ForegroundColor Cyan
$refused = [ordered]@{
    "8.8.8.8" = "*public address*"; "1.1.1.1" = "*public address*"; "73.12.4.9" = "*public address*"
    "9.255.255.255" = "*public address*"; "11.0.0.0" = "*public address*"
    "172.15.255.255" = "*public address*"; "172.32.0.0" = "*public address*"
    "192.167.255.255" = "*public address*"; "192.169.0.0" = "*public address*"
    "100.63.255.255" = "*public address*"; "100.128.0.0" = "*public address*"
    "169.253.255.255" = "*public address*"; "126.255.255.255" = "*public address*"; "128.0.0.1" = "*public address*"
    "224.0.0.1" = "*public address*"; "255.255.255.255" = "*public address*"
    "252.0.0.1" = "*public address*"; "254.128.0.1" = "*public address*"
    "2001:4860:4860::8888" = "*public address*"; "fbff::1" = "*public address*"; "fec0::1" = "*public address*"; "ff02::1" = "*public address*"
    "0.0.0.0" = "*every interface*"; "::" = "*every interface*"
    "::ffff:192.168.1.182" = "*IPv4 address in IPv6 form*"
    "localhost" = "*not an IP address*"; "hub.local" = "*not an IP address*"; "any" = "*not an IP address*"
    "192.168.1.0/24" = "*not an IP address*"; "192.168.1.182:2222" = "*not an IP address*"
    "1" = "*four decimal numbers*"; "127.1" = "*four decimal numbers*"; "0x7f.0.0.1" = "*"; "192.168.001.182" = "*four decimal numbers*"
    "" = "*no address*"
}
foreach ($a in $refused.Keys) {
    $k = Kind $a
    Check ($k.state -ceq "unknown" -and "$($k.reason)" -like $refused[$a]) ("'" + $a + "' is refused, saying why (" + $k.reason + ")")
}

Write-Host ""
Write-Host "--- and it must be this machine's ---" -ForegroundColor Cyan
$here4 = @("127.0.0.1", "::1", "192.168.1.182", "fe80::1%12")
$r = Resolve-HordeListenAddress -Address "192.168.1.182" -LocalAddresses $here4
Check ($r.state -ceq "known" -and $r.value.address -ceq "192.168.1.182") "CONTROL: an address an interface holds is taken"
$r = Resolve-HordeListenAddress -Address "192.168.1.183" -LocalAddresses $here4
Check ($r.state -ceq "unknown" -and $r.reason -like "*private (RFC 1918), but no interface of this machine that is up holds it now*") ("a private address no interface holds is refused, saying so (" + $r.reason + ")")
Check ((Resolve-HordeListenAddress -Address "127.0.0.2" -LocalAddresses @()).state -ceq "known") "loopback is always this machine's"
Check ((Resolve-HordeListenAddress -Address "8.8.8.8" -LocalAddresses @("8.8.8.8")).reason -like "*public address*") "a public address is refused even when an interface holds it: the rule comes first"
$mine = @(Get-HordeLocalAddresses)
Check ($mine -contains "127.0.0.1") ("CONTROL: this machine's interfaces are read, loopback among them (" + $mine.Count + " addresses)")

Write-Host ""
Write-Host "--- who a node may come from: single private addresses, never any, never loopback ---" -ForegroundColor Cyan
$f = Resolve-HordeAllowFrom -Addresses @("192.168.1.156")
Check ($f.state -ceq "known" -and (@($f.value) -join ",") -ceq "192.168.1.156") "CONTROL: one private address"
$f = Resolve-HordeAllowFrom -Addresses @("192.168.1.156,10.0.0.5", " 100.101.102.103 ", "192.168.1.156")
Check ($f.state -ceq "known" -and (@($f.value) -join ",") -ceq "10.0.0.5,100.101.102.103,192.168.1.156") ("a comma list, as -File delivers it, split, trimmed, each once, sorted (" + (@($f.value) -join ",") + ")")
foreach ($bad in @(@(), @(""), @("any"), @("*"), @("0.0.0.0"), @("8.8.8.8"), @("192.168.1.156", "8.8.8.8"), @("127.0.0.1"), @("192.168.1.0/24"), @("node.local"))) {
    $f = Resolve-HordeAllowFrom -Addresses $bad
    Check ($f.state -ceq "unknown") ("refused as nodes' addresses: '" + ($bad -join ",") + "' (" + $f.reason + ")")
}

Write-Host ""
Write-Host "--- horde listen, run as a user would: refused before anything listens ---" -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP ("horde-listen-address-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $envs = @{ HORDE_HOME = $tmp }
    foreach ($case in @(
            @{ a = @("-Address", "8.8.8.8"); want = "*public address*" },
            @{ a = @("-Address", "0.0.0.0"); want = "*every interface*" },
            @{ a = @("-Address", "::"); want = "*every interface*" },
            @{ a = @("-Address", "my-hub"); want = "*not an IP address*" },
            @{ a = @("-Address", "192.168.254.253"); want = "*no interface of this machine*" },
            @{ a = @("-Address", "127.0.0.1", "-AllowFrom", "192.168.1.156"); want = "*-AllowFrom goes with a network -Address*" })) {
        $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("listen") + $case.a + @("-Seconds", "1")) -Env $envs
        Check ($r.code -eq 1 -and $r.out -like $case.want -and $r.out -notlike "*listening on*") ("horde listen " + ($case.a -join " ") + ": exit 1, refused before anything listens (exit " + $r.code + ": " + $r.out.Trim() + ")")
    }
    Check (-not (Test-Path -LiteralPath (Join-Path $tmp "hub\listen"))) "and nothing was ever written for a listener"
} finally { if ((Split-Path -Leaf $tmp) -match '^horde-listen-address-[0-9a-f]{32}$') { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }

Complete-HordeSuite -Success "the hub listens only on loopback or a private address this machine holds, and lets in only private addresses: never a public one"
