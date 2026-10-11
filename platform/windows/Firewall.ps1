# platform/windows/Firewall.ps1 - the Windows Defender Firewall adapter for core/FirewallPort.ps1.
#
# WHAT IT DOES. It reads, writes and removes the one inbound rule whose Name the port gives it, through
# the NetSecurity module's cmdlets, always by -Name and never by a pattern, a group or a display name, so
# no other rule on the machine is read or touched (the port's OWNED BY NAME). Set replaces the rule whole
# - removed by that name, then made again - so a rule changed by hand is put back to the spec rather than
# merged with. The rule has no program: the port's spec names no listener.
#
# CATEGORY, READ ONLY. The port asks which category the network holding the listen address is in: the
# interface that holds the address (Get-NetIPAddress), then that interface's connection profile
# (Get-NetConnectionProfile), its NetworkCategory returned as Windows names it. Nothing here sets a
# category; the founder does that, if he chooses to, in Windows' own settings.
#
# NetSecurity is imported from Windows PowerShell's own module folder by its path, not found through
# PSModulePath: a PSModulePath another shell left (PowerShell 7's) breaks module discovery in 5.1, and
# the firewall must not depend on what the founder's shell set.
#
# NEVER RUN BY A SUITE. Every suite drives the port through a stand-in adapter (test/test-firewall-port.ps1);
# this file is read, never run, by the tests, so no test can make, change or delete a real rule.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Test-HordeWindowsFirewallElevated {
    # Is this process an elevated administrator? Changing a firewall rule needs one.
    $p = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    return [bool]$p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-HordeWindowsFirewallModule {
    # NetSecurity from Windows PowerShell's own module folder (header).
    if ($null -eq (Get-Module -Name NetSecurity)) { Import-Module -Name (Join-Path $PSHOME "Modules\NetSecurity") -ErrorAction Stop }
}

function Get-HordeWindowsNetworkCategory {
    # The NetworkCategory of the connection profile on the interface that holds -Address, or $null when
    # no interface holds it or that interface has no profile (header, CATEGORY).
    param([Parameter(Mandatory = $true)][string]$Address)
    foreach ($m in @("NetTCPIP", "NetConnection")) { if ($null -eq (Get-Module -Name $m)) { Import-Module -Name (Join-Path $PSHOME ("Modules" + $m)) -ErrorAction Stop } }
    $ip = @(Get-NetIPAddress -IPAddress $Address -ErrorAction SilentlyContinue)
    if ($ip.Count -eq 0) { return $null }
    $c = @(Get-NetConnectionProfile -InterfaceIndex $ip[0].InterfaceIndex -ErrorAction SilentlyContinue)
    if ($c.Count -eq 0) { return $null }
    return ("" + $c[0].NetworkCategory)
}

function Get-HordeWindowsFirewallRule {
    # The rule named -Name in the port's spec shape, or $null when there is none.
    param([Parameter(Mandatory = $true)][string]$Name)
    Import-HordeWindowsFirewallModule
    $r = @(Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue)
    if ($r.Count -eq 0) { return $null }
    $a = $r[0] | Get-NetFirewallAddressFilter
    $p = $r[0] | Get-NetFirewallPortFilter
    $profiles = @("$($r[0].Profile)".Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Sort-Object)
    return [pscustomobject][ordered]@{
        name = "$($r[0].Name)"; direction = "$($r[0].Direction)"; action = "$($r[0].Action)"; protocol = "$($p.Protocol)"
        localAddress = (@($a.LocalAddress) -join ","); localPort = "$(@($p.LocalPort) -join ',')"
        remoteAddresses = @(@($a.RemoteAddress) | Sort-Object); profiles = $profiles
        count = $r.Count
    }
}

function Set-HordeWindowsFirewallRule {
    # Make the rule $Spec.name exactly $Spec: every rule of that name removed, then one made.
    param([Parameter(Mandatory = $true)]$Spec)
    Import-HordeWindowsFirewallModule
    Remove-HordeWindowsFirewallRule -Name $Spec.name
    $null = New-NetFirewallRule -Name $Spec.name -DisplayName $Spec.name -Description "Horde: lets this hub's nodes reach its listener while horde listen runs; removed when it stops." `
        -Direction $Spec.direction -Action $Spec.action -Protocol $Spec.protocol -LocalAddress $Spec.localAddress -LocalPort ([string]$Spec.localPort) `
        -RemoteAddress @($Spec.remoteAddresses) -Profile (@($Spec.profiles) -join ",") -Enabled True -ErrorAction Stop
}

function Remove-HordeWindowsFirewallRule {
    # Remove every rule named -Name; none is not an error.
    param([Parameter(Mandatory = $true)][string]$Name)
    Import-HordeWindowsFirewallModule
    $r = @(Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue)
    if ($r.Count -gt 0) { Remove-NetFirewallRule -Name $Name -ErrorAction Stop }
}

function Register-HordeWindowsFirewall {
    $blocks = @{
        Name     = "windows"
        Applies  = { [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT }
        Elevated = { Test-HordeWindowsFirewallElevated }
        Get      = { param($Name) Get-HordeWindowsFirewallRule -Name $Name }
        Set      = { param($Spec) Set-HordeWindowsFirewallRule -Spec $Spec }
        Remove   = { param($Name) Remove-HordeWindowsFirewallRule -Name $Name }
        Category = { param($Address) Get-HordeWindowsNetworkCategory -Address $Address }
    }
    Register-HordeFirewall @blocks
}
Register-HordeWindowsFirewall
