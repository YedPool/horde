# cli/ListenFirewall - what `horde listen` does about the firewall before it listens and after it stops.
#
# WHY HERE (mesh v1, 2026-10-11). The listen address is the founder's to pick (core/ListenAddress.ps1);
# on any address but loopback the hub keeps ONE inbound rule of its own while it listens and removes it
# when it stops (core/FirewallPort.ps1). Deciding which rule, refusing what cannot be done safely, and
# saying the exact command the founder can run are this file's; the rule itself is the port's and its
# platform adapter's. Every function here takes the firewall adapter as a parameter, so the suite
# drives it with a stand-in and no suite ever reaches a real firewall.
#
# REFUSED, EACH WITH THE REASON, BEFORE ANYTHING LISTENS:
#   - port 0 on a network address: a node dials a port it was told, so -Port names it;
#   - nobody to let in: no -AllowFrom and no enrolled node with a last-known address
#     (`horde hub enroll -Address`), since a rule that lets in "any" is never made;
#   - no firewall adapter for this system;
#   - a listen address on a network the firewall treats as Public, without -AllowPublicProfile: the rule
#     would never apply there, so the founder picks one of the two ways out, named in the refusal
#     (Get-HordeListenProfileRefusal);
#   - a process that is not elevated: the rule needs an administrator, and Horde never elevates itself,
#     so the refusal carries the one line to run in an elevated PowerShell (Get-HordeListenElevationCommand).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Join-HordeListenProfileWords {
    # "Domain and Private", "Domain, Private and Public": the profiles as the said-line and refusals put them.
    param([string[]]$Profiles)
    $p = @($Profiles)
    if ($p.Count -le 1) { return ($p -join "") }
    return ((@($p[0..($p.Count - 2)]) -join ", ") + " and " + $p[-1])
}

function Get-HordeListenProfileRefusal {
    # Why a listener on -Address, a network of profile -NetworkProfile, is refused while the rule holds only
    # -Profiles, with both ways out: one paragraph.
    param([Parameter(Mandatory = $true)][string]$Address, [Parameter(Mandatory = $true)][string]$NetworkProfile, [string[]]$Profiles)
    return ("horde listen will not listen on " + $Address + ": that address is on a network the firewall treats as " + $NetworkProfile + ", and the listener's rule holds only the " + (Join-HordeListenProfileWords -Profiles $Profiles) + " profiles, so it would never apply and no node could connect. Choose one: run horde listen again with -AllowPublicProfile, which adds the Public profile to this one rule only (it stays held to " + $Address + ", its port and the nodes' addresses); or set that network to Private in the system's network settings, which also turns on every other inbound rule the system keeps for Private networks (network discovery, remote assistance, UPnP and more).")
}

function Open-HordeListenFirewall {
    # The firewall for a listener on -Where (Resolve-HordeListenAddress's value) and -Port, through
    # -Firewall (Get-HordeFirewall's answer). Answers { ok; rule (its name, "" when none is needed); said;
    # reason }. -AllowFrom is the addresses the founder named; with none, -Known is used (the enrolled
    # nodes' last-known addresses). -AllowPublicProfile adds the Public profile to the rule; without it, a
    # listen address on a Public network is refused before anything is written.
    param([Parameter(Mandatory = $true)]$Where, [int]$Port, [Parameter(Mandatory = $true)][string]$HubId, [Parameter(Mandatory = $true)]$Firewall, [string[]]$AllowFrom = @(), [string[]]$Known = @(), [Parameter(Mandatory = $true)][string]$Root, [int]$Seconds = 0, [switch]$AllowPublicProfile)
    $out = [pscustomobject]@{ ok = $false; rule = ""; said = ""; reason = "" }
    if ($Where.loopback) { $out.ok = $true; $out.said = "loopback needs no firewall rule"; return $out }
    if ($Port -lt 1) { $out.reason = "a listener on " + $Where.address + " needs a fixed port the nodes are told: give -Port"; return $out }
    $from = @(@($AllowFrom) | Where-Object { "$_".Trim() -ne "" })
    $whence = "-AllowFrom"
    if ($from.Count -eq 0) { $from = @(@($Known) | Where-Object { "$_".Trim() -ne "" }); $whence = "the enrolled nodes' last-known addresses" }
    $spec = New-HordeListenRuleSpec -HubId $HubId -Address $Where.address -Port $Port -AllowFrom $from -AllowPublicProfile:$AllowPublicProfile
    if ($spec.state -cne "known") { $out.reason = "no firewall rule can be made for " + $Where.address + ": " + $spec.reason; return $out }
    if ($Firewall.state -cne "known") { $out.reason = "the listener on " + $Where.address + " cannot be kept to its nodes: " + $Firewall.reason; return $out }
    $fw = $Firewall.value
    # The network's profile before elevation, so a Public network is said before the founder elevates for
    # nothing. A profile that cannot be read is no refusal: the rule is still kept to its nodes.
    $net = Get-HordeListenNetworkProfile -Firewall $fw -Address $Where.address
    if ($net.state -ceq "known" -and @(@($spec.value.profiles) | Where-Object { $_ -ceq $net.value }).Count -eq 0) { $out.reason = Get-HordeListenProfileRefusal -Address $Where.address -NetworkProfile $net.value -Profiles $spec.value.profiles; return $out }
    $elevated = $false
    try { $elevated = (@(& $fw.elevated) | Select-Object -Last 1) -eq $true } catch { }
    if (-not $elevated) {
        $out.reason = "listening on " + $Where.address + " needs its firewall rule, and that needs an administrator; Horde never elevates itself. In an elevated PowerShell, run: " + (Get-HordeListenElevationCommand -Root $Root -Address $Where.address -Port $Port -AllowFrom $AllowFrom -Seconds $Seconds -AllowPublicProfile:$AllowPublicProfile)
        return $out
    }
    $s = Sync-HordeListenRule -Firewall $fw -Spec $spec.value
    if (-not $s.ok) { $out.reason = $s.reason; return $out }
    $out.ok = $true
    $out.rule = $spec.value.name
    $out.said = "firewall rule '" + $spec.value.name + "' " + $s.did + ": TCP " + $Where.address + ":" + $Port + " from " + (@($spec.value.remoteAddresses) -join ", ") +  " (" + $whence + "), " + (Join-HordeListenProfileWords -Profiles $spec.value.profiles) + " profiles only"
    return $out
}

function Close-HordeListenFirewall {
    # Remove the rule Open-HordeListenFirewall made, if it made one. Answers what was done, in words.
    param([Parameter(Mandatory = $true)]$Firewall, [string]$Rule = "")
    if ($Rule -eq "") { return "" }
    if ($Firewall.state -cne "known") { return ("the firewall rule '" + $Rule + "' could not be removed: " + $Firewall.reason) }
    $why = Remove-HordeListenRule -Firewall $Firewall.value -Name $Rule
    if ($why -ne "") { return $why }
    return ("firewall rule '" + $Rule + "' removed")
}
