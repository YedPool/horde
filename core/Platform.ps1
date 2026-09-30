# core/Platform - the machine core runs on: the namespace its process ids live in, and how it reads
# its own process table.
#
# WHY A SEAM. The read model checks a session's process against the process table, and compares a
# pid a host reports with it only inside one namespace (core/HostPort.ps1, "PID AND CWD CARRY A
# NAMESPACE"). Both used to be Windows calls written into core (review of PR #31, finding 6). A node
# on another system (the remote plan's R12) supplies its own platform; this file holds the seam and
# the one platform Horde runs on today, Windows, and no other implementation.
#
# A platform is { name; processSpace; processTable }: processTable is a script block returning the
# process table as core/identity takes it - a core/tristate answer holding a hashtable keyed by pid of
# { pid; name; created (UTC); commandLine } - or unknown with the reason.

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

# The namespaces a pid or path can live in, as core/HostPort.ps1's rows name them.
$script:HordeProcessSpacePattern = '^(windows|posix|synthetic|wsl:[A-Za-z0-9._-]{1,64})$'

function New-HordePlatform {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ProcessSpace,
        [Parameter(Mandatory = $true)][scriptblock]$ProcessTable
    )
    if ($ProcessSpace -cnotmatch $script:HordeProcessSpacePattern) { throw ("'" + $ProcessSpace + "' is not a process namespace core knows: windows, posix, synthetic or wsl:<distro>") }
    return [pscustomobject]@{ PSTypeName = "Horde.Platform"; name = $Name; processSpace = $ProcessSpace; processTable = $ProcessTable }
}

function Assert-HordePlatform {
    param($Platform)
    if ($null -eq $Platform -or @($Platform.PSObject.TypeNames) -notcontains "Horde.Platform") { throw "-Platform must be made by New-HordePlatform or Get-HordeLocalPlatform" }
}

function Get-HordeProjectionProcessTable {
    # The Windows platform's process table: core/identity's shape plus each process's command line,
    # the only involuntary witness to one conversation running in two processes (YedPool/wezfleet
    # lib/Common.ps1:656-662, "THE COMMAND LINE IS THE ONLY INVOLUNTARY WITNESS"). Read-only CIM.
    return (Invoke-HordeRead -What "the process table" -Read {
        $t = @{}
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, Name, CreationDate, CommandLine -ErrorAction Stop)) {
            $created = $null
            if ($null -ne $p.CreationDate) { $created = ([datetime]$p.CreationDate).ToUniversalTime() }
            $t[[int]$p.ProcessId] = [pscustomobject]@{ pid = [int]$p.ProcessId; name = "$($p.Name)"; created = $created; commandLine = $p.CommandLine }
        }
        return $t
    })
}

function Get-HordeLocalPlatform {
    # The platform Horde runs on today. The one place core names the Windows process namespace.
    return (New-HordePlatform -Name "windows" -ProcessSpace "windows" -ProcessTable { Get-HordeProjectionProcessTable })
}
