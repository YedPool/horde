# core/FirewallPort.ps1 - the port through which `horde listen` keeps ONE inbound firewall rule of its
# own open while it listens on a network address, and nothing else.
#
# WHY (mesh v1, 2026-10-11). On loopback the hub needs no rule. On the office LAN, Tailscale or
# WireGuard it does, and the founder's rules say how wide: only TCP, only to the listen address and port,
# only from the enrolled nodes' addresses (or the ones -AllowFrom names), only on the Private and Domain
# profiles - never Public - and only while `horde listen` runs. A system's firewall is its own business,
# so each system that has one supplies platform/<name>/Firewall.ps1, found by folder and registered here,
# as platform/<name>/WindowFollow.ps1 registers with core/WindowFollowPort.ps1. A CALLER NAMES NO
# PLATFORM.
#
# OWNED BY NAME, AND ONLY THAT NAME. The rule is "Horde listen <hubId>". This port asks an adapter about,
# writes and removes that one name and never any other, so another rule - Windows' own, the one the
# founder's server install left disabled, anyone's - is never read, changed or deleted. Writing is
# idempotent: the rule as it is is compared with the rule as it should be, and nothing is written when
# they agree.
#
# ELEVATION IS THE FOUNDER'S TO GIVE, NEVER TAKEN. Changing a rule needs an administrator. When the
# process is not elevated, the caller refuses with the exact one line to run in an elevated PowerShell
# (Get-HordeListenElevationCommand); nothing here, or in an adapter, elevates itself.
#
# ADAPTER CONTRACT. platform/<name>/Firewall.ps1, dot-sourced at the caller's scope, calls
# Register-HordeFirewall with:
#   Applies   { }                -> $true when this adapter is for the running system
#   Elevated  { }                -> $true when this process may change the firewall
#   Get       param($Name)       -> $null when no rule has that name, or the rule in the spec's shape
#   Set       param($Spec)       -> make the rule $Spec.name exactly $Spec (create it, or replace it whole)
#   Remove    param($Name)       -> remove every rule with that name; none is not an error
# A spec is { name; direction "Inbound"; action "Allow"; protocol "TCP"; localAddress; localPort;
# remoteAddresses (sorted); profiles ("Domain", "Private") }: no program, so it names no listener.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ListenAddress.ps1")

if ($null -eq (Get-Variable -Name HordeFirewalls -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeFirewalls = New-Object System.Collections.ArrayList }
$script:HordeListenRulePrefix = "Horde listen "
$script:HordeListenRuleProfiles = @("Domain", "Private")

function Register-HordeFirewall {
    # Called by platform/<name>/Firewall.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Applies,
        [Parameter(Mandatory = $true)][scriptblock]$Elevated,
        [Parameter(Mandatory = $true)][scriptblock]$Get,
        [Parameter(Mandatory = $true)][scriptblock]$Set,
        [Parameter(Mandatory = $true)][scriptblock]$Remove
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a platform name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($known in @($script:HordeFirewalls)) { if ($known.name -ceq $Name) { $script:HordeFirewalls.Remove($known) } }
    [void]$script:HordeFirewalls.Add([pscustomobject]@{ name = $Name; applies = $Applies; elevated = $Elevated; get = $Get; set = $Set; remove = $Remove })
}

function Get-HordeFirewallFiles {
    # The adapter files, found by folder: platform/<name>/Firewall.ps1, for the caller to dot-source.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $platforms = Join-Path $Root "platform"
    if (-not (Test-Path -LiteralPath $platforms -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $platforms -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Firewall.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeFirewall {
    # The adapter for this system, as an answer: the first registered one whose Applies is exactly true.
    if ($script:HordeFirewalls.Count -eq 0) { return (New-HordeUnknown -Reason "no firewall adapter is loaded, so the hub cannot keep its listener reachable from its nodes alone") }
    foreach ($a in @($script:HordeFirewalls)) {
        $here = $null
        try { $here = @(& $a.applies) | Select-Object -Last 1 } catch { continue }
        if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $a) }
    }
    return (New-HordeUnknown -Reason "no firewall adapter is for this system")
}

function Get-HordeListenRuleName {
    # The one rule a hub's listener owns: "Horde listen <hubId>".
    param([Parameter(Mandatory = $true)][string]$HubId)
    if ($HubId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { throw ("not a hub id: '" + $HubId + "'") }
    return ($script:HordeListenRulePrefix + $HubId)
}

function New-HordeListenRuleSpec {
    # The rule as it should be, as an answer: known spec, or unknown with the reason. -Address is the
    # listen address (Resolve-HordeListenAddress's, never loopback: loopback needs no rule), -AllowFrom
    # the nodes' addresses (Resolve-HordeAllowFrom). Pure.
    param([Parameter(Mandatory = $true)][string]$HubId, [Parameter(Mandatory = $true)][string]$Address, [Parameter(Mandatory = $true)][int]$Port, [string[]]$AllowFrom)
    $k = Get-HordeListenAddressKind -Address $Address
    if ($k.state -cne "known") { return $k }
    if ($k.value.loopback) { return (New-HordeUnknown -Reason ("'" + $Address + "' is loopback, which needs no firewall rule")) }
    if ($Port -lt 1 -or $Port -gt 65535) { return (New-HordeUnknown -Reason ("port " + $Port + " is not a TCP port")) }
    $from = Resolve-HordeAllowFrom -Addresses $AllowFrom
    if ($from.state -cne "known") { return $from }
    return (New-HordeKnown -Value ([pscustomobject][ordered]@{ name = (Get-HordeListenRuleName -HubId $HubId); direction = "Inbound"; action = "Allow"; protocol = "TCP"; localAddress = $k.value.address; localPort = $Port; remoteAddresses = @($from.value); profiles = @($script:HordeListenRuleProfiles) }))
}

function Test-HordeListenRuleSame {
    # Is the rule -Have (an adapter's Get) exactly -Want (a spec)? Every field, lists as sorted sets.
    param($Have, [Parameter(Mandatory = $true)]$Want)
    if ($null -eq $Have) { return $false }
    foreach ($f in @("name", "direction", "action", "protocol", "localAddress")) { if ("$($Have.$f)" -cne "$($Want.$f)") { return $false } }
    if ([int]$Have.localPort -ne [int]$Want.localPort) { return $false }
    foreach ($f in @("remoteAddresses", "profiles")) {
        $h = (@(@($Have.$f) | ForEach-Object { "" + $_ } | Sort-Object -Unique) -join ",")
        $w = (@(@($Want.$f) | ForEach-Object { "" + $_ } | Sort-Object -Unique) -join ",")
        if ($h -cne $w) { return $false }
    }
    return $true
}

function Sync-HordeListenRule {
    # Make the firewall hold -Spec, through -Firewall (an adapter), touching no rule of another name.
    # Answers { ok; did ("unchanged", "made" or "replaced"); reason }. Never elevates: an adapter that says
    # this process may not change the firewall is refused before anything is asked of it.
    param([Parameter(Mandatory = $true)]$Firewall, [Parameter(Mandatory = $true)]$Spec)
    $out = [pscustomobject]@{ ok = $false; did = ""; reason = "" }
    if ("$($Spec.name)".StartsWith($script:HordeListenRulePrefix, [System.StringComparison]::Ordinal) -eq $false) { $out.reason = "the rule '" + $Spec.name + "' is not one this port owns"; return $out }
    $elevated = $false
    try { $elevated = (@(& $Firewall.elevated) | Select-Object -Last 1) -eq $true } catch { }
    if (-not $elevated) { $out.reason = "changing the firewall needs an administrator, and this process is not elevated"; return $out }
    $have = $null
    try { $have = & $Firewall.get $Spec.name } catch { $out.reason = "the firewall rule '" + $Spec.name + "' could not be read: " + $_.Exception.Message; return $out }
    if (Test-HordeListenRuleSame -Have $have -Want $Spec) { $out.ok = $true; $out.did = "unchanged"; return $out }
    try { $null = & $Firewall.set $Spec } catch { $out.reason = "the firewall rule '" + $Spec.name + "' could not be written: " + $_.Exception.Message; return $out }
    $back = $null
    try { $back = & $Firewall.get $Spec.name } catch { }
    if (-not (Test-HordeListenRuleSame -Have $back -Want $Spec)) { $out.reason = "the firewall rule '" + $Spec.name + "' did not read back as written"; return $out }
    $out.ok = $true
    $out.did = $(if ($null -eq $have) { "made" } else { "replaced" })
    return $out
}

function Remove-HordeListenRule {
    # Remove the rule -Name through -Firewall, and only it. Answers "" when it is gone (or was never
    # there), or why not.
    param([Parameter(Mandatory = $true)]$Firewall, [Parameter(Mandatory = $true)][string]$Name)
    if (-not $Name.StartsWith($script:HordeListenRulePrefix, [System.StringComparison]::Ordinal)) { return ("the rule '" + $Name + "' is not one this port owns") }
    try { $null = & $Firewall.remove $Name } catch { return ("the firewall rule '" + $Name + "' could not be removed: " + $_.Exception.Message) }
    $left = $null
    try { $left = & $Firewall.get $Name } catch { }
    if ($null -ne $left) { return ("the firewall rule '" + $Name + "' is still there after it was removed") }
    return ""
}

function Get-HordeListenElevationCommand {
    # The exact one line the founder runs in an elevated PowerShell to start this listener: Windows
    # PowerShell running this Horde's horde.ps1 with the same arguments. Never run by Horde itself.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Address, [Parameter(Mandatory = $true)][int]$Port, [string[]]$AllowFrom = @(), [int]$Seconds = 0)
    $line = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "horde.ps1") + "`" listen -Address " + $Address + " -Port " + $Port
    $from = @(@($AllowFrom) | Where-Object { "$_".Trim() -ne "" })
    if ($from.Count -gt 0) { $line = $line + " -AllowFrom " + ($from -join ",") }
    if ($Seconds -gt 0) { $line = $line + " -Seconds " + $Seconds }
    return $line
}
