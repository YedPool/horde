# core/Namespace - which machine and which process space a pid, procStart or path belongs to.
#
# WHY (remote plan step R11, planning/execution-plan-remote.md). A pid is a number only one table can
# read: the process table of one machine, in one process space. Hosts decision 5 already tags each pid
# and cwd with its space (windows, wsl:<distro>, posix, synthetic: core/Platform.ps1), because a WSL
# pid looked up in the Windows table names an unrelated process. Remote work adds the machine: pid
# 1234 on the always-on box is not pid 1234 here. So a pid, procStart or path that leaves a node
# carries ns { device, space } - the device id of core/Device.ps1 (R7) and the space of the platform
# that read it - and these rules decide what may be done with it:
#   (a) a pid is looked up only in its own device's table, in its own space (Test-HordeNamespaceLocal;
#       core/Identity.ps1's process check refuses before it touches the table);
#   (b) two pids are one process only when device, space, pid and procStart all match
#       (Test-HordeSameProcess) - pid and procStart alone match two machines' processes;
#   (c) a path from another device, or another space, is displayed and never opened here
#       (Test-HordePathOpenable): C:\x on the box and C:\x here are two folders;
#   (d) the agent's pidDomain is its claim, never the device. Measured (remote design M-01): it is
#       "win32:<user>" in every control file, so two machines with one user name write the same value.
#       Nothing here reads it, and New-HordeNamespace has no way to take it.
#
# IDENTITY IS NOT LOCATION. The device names the machine and nothing more: never a host name, which is
# a handle for people (wezfleet-v3-rewrite-proposal.html:105-111, carried by R7).
#
# Every answer is a core/tristate answer: a namespace that is missing or malformed is unknown with the
# reason, never assumed local and never a match.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Platform.ps1")

# The device id's one spelling, as core/Device.ps1 writes it and schema/node-manifest.v1 states it.
# ANCHORED WITH \z, NOT $: in .NET a final $ also matches before a trailing newline, so "<id>\n" passed
# as a device and "windows\n" as a space (review of this PR; core/Schema.ps1 records the same trap from
# PR #15). The space pattern is core/Platform.ps1's, re-anchored the same way.
$script:HordeNamespaceDevicePattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeNamespaceSpacePattern = ($script:HordeProcessSpacePattern -replace '\$$', '\z')
# A pid is a positive whole number that fits a 32-bit process id; anything else is not a pid.
$script:HordeNamespacePidMax = [long][int]::MaxValue

function New-HordeNamespace {
    # { device; space }, refused unless both are well formed. The space vocabulary is core/Platform.ps1's.
    param([string]$Device, [string]$Space)
    if ($Device -cnotmatch $script:HordeNamespaceDevicePattern) { throw ("'" + $Device + "' is not a device id: a namespace's device is the lower-case id core/Device.ps1 makes, never a host name") }
    if ($Space -cnotmatch $script:HordeNamespaceSpacePattern) { throw ("'" + $Space + "' is not a process space core knows: windows, posix, synthetic or wsl:<distro>") }
    return [pscustomobject]@{ PSTypeName = "Horde.Namespace"; device = $Device; space = $Space }
}

function Get-HordeLocalNamespace {
    # This machine's namespace: its device id (the caller reads it once, core/Device.ps1) and the space
    # of the platform whose process table it reads.
    param([Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)]$Platform)
    return (New-HordeNamespace -Device $DeviceId -Space "$($Platform.processSpace)")
}

function Get-HordeNamespaceProblem {
    # Why a value cannot be read as a namespace, or "" when it can. Looked up, never dereferenced, so a
    # missing member is a reason under strict mode, not an error.
    param($Namespace)
    if ($null -eq $Namespace) { return "it names no namespace" }
    $d = $Namespace.PSObject.Properties["device"]
    $s = $Namespace.PSObject.Properties["space"]
    if ($null -eq $d -or $null -eq $s) { return "its namespace does not give both a device and a space" }
    $dv = ""; if ($null -ne $d) { $dv = "$($d.Value)" }
    $sv = ""; if ($null -ne $s) { $sv = "$($s.Value)" }
    if ($dv -cnotmatch $script:HordeNamespaceDevicePattern) { return ("its namespace's device '" + $dv + "' is not a device id") }
    if ($sv -cnotmatch $script:HordeNamespaceSpacePattern) { return ("its namespace's space '" + $sv + "' is not one core knows") }
    return ""
}

function Test-HordeNamespaceLocal {
    # (a) May a pid of -Namespace be looked up in -Local's process table? Known true only when the device
    # and the space are both this machine's; known false, with the reason, when either differs; unknown
    # when either namespace cannot be read.
    param($Namespace, $Local)
    $why = Get-HordeNamespaceProblem $Local
    if ($why -ne "") { return (New-HordeUnknown -Reason ("this machine's namespace cannot be read: " + $why)) }
    $why = Get-HordeNamespaceProblem $Namespace
    if ($why -ne "") { return (New-HordeUnknown -Reason ("the pid cannot be placed: " + $why)) }
    if ("$($Namespace.device)" -cne "$($Local.device)") { return New-HordeAnswer -State "known" -Value $false -Reason ("the pid belongs to device " + $Namespace.device + ", so it is never looked up here") }
    if ("$($Namespace.space)" -cne "$($Local.space)") { return New-HordeAnswer -State "known" -Value $false -Reason ("the pid belongs to space " + $Namespace.space + ", not " + $Local.space + ", so it is never looked up in this table") }
    return (New-HordeKnown -Value $true)
}

function ConvertTo-HordeNamespaceTicks {
    # A procStart as an integer tick count, or $null. Compared as an integer: as text, "0" + the same
    # ticks would be another time (core/Identity.ps1, Get-HordeProcessVerdict).
    param($ProcStart)
    $t = [long]0
    if ($null -eq $ProcStart -or -not [long]::TryParse("$ProcStart", [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$t)) { return $null }
    return $t
}

function ConvertTo-HordeNamespacePid {
    # A pid as a long, or $null: a single whole number from 1 to the largest process id, given as a
    # number or as digits. A list, zero, a negative or an oversized value is not a pid - [long] on
    # "99999999999999999999" threw instead of answering (review of this PR).
    param($Value)
    if ($null -eq $Value -or $Value -is [System.Array]) { return $null }
    $n = [long]0
    if (-not [long]::TryParse("$Value", [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $null }
    if ($n -lt 1 -or $n -gt $script:HordeNamespacePidMax) { return $null }
    return $n
}

function Test-HordeSameProcess {
    # (b) Are -A and -B, each { ns; pid; procStart }, one process? Known true only when device, space,
    # pid and procStart all match; known false when all are readable and any differs; unknown when any
    # is missing - never a match on the parts that are there. pidDomain, if a row carries it, is not read.
    param($A, $B)
    foreach ($side in @(@("first", $A), @("second", $B))) {
        $row = $side[1]
        if ($null -eq $row) { return (New-HordeUnknown -Reason ("the " + $side[0] + " process is not given")) }
        $nsProp = $row.PSObject.Properties["ns"]
        $why = Get-HordeNamespaceProblem $(if ($null -ne $nsProp) { $nsProp.Value } else { $null })
        if ($why -ne "") { return (New-HordeUnknown -Reason ("the " + $side[0] + " process cannot be placed: " + $why)) }
        $pidProp = $row.PSObject.Properties["pid"]
        if ($null -eq $pidProp -or $null -eq (ConvertTo-HordeNamespacePid $pidProp.Value)) { return (New-HordeUnknown -Reason ("the " + $side[0] + " process has no pid")) }
        $psProp = $row.PSObject.Properties["procStart"]
        if ($null -eq $psProp -or $null -eq (ConvertTo-HordeNamespaceTicks $psProp.Value)) { return (New-HordeUnknown -Reason ("the " + $side[0] + " process has no procStart that is a tick count, so a pid match would not show it is the same process")) }
    }
    $same = ("$($A.ns.device)" -ceq "$($B.ns.device)") -and ("$($A.ns.space)" -ceq "$($B.ns.space)") -and ((ConvertTo-HordeNamespacePid $A.pid) -eq (ConvertTo-HordeNamespacePid $B.pid)) -and ((ConvertTo-HordeNamespaceTicks $A.procStart) -eq (ConvertTo-HordeNamespaceTicks $B.procStart))
    return (New-HordeKnown -Value ([bool]$same))
}

function Test-HordePathOpenable {
    # (c) May a path of -Namespace be opened on this machine? Known true only for this device and space;
    # otherwise known false: the path is displayed, never opened. Unknown when it cannot be placed.
    param($Namespace, $Local)
    $why = Get-HordeNamespaceProblem $Local
    if ($why -ne "") { return (New-HordeUnknown -Reason ("this machine's namespace cannot be read: " + $why)) }
    $why = Get-HordeNamespaceProblem $Namespace
    if ($why -ne "") { return (New-HordeUnknown -Reason ("the path cannot be placed, so it is not opened: " + $why)) }
    if ("$($Namespace.device)" -cne "$($Local.device)" -or "$($Namespace.space)" -cne "$($Local.space)") {
        return New-HordeAnswer -State "known" -Value $false -Reason ("the path is on device " + $Namespace.device + " in space " + $Namespace.space + ": it is displayed, never opened here")
    }
    return (New-HordeKnown -Value $true)
}
