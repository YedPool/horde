# core/ServiceHostPort - the three things the supervisor of services (core/Services.ps1) needs from
# the machine it runs on and cannot do in a way that is the same on every system: tell whether the
# person is at the machine, start a process that outlives the pass that started it, and ask a window
# to close.
#
# WHY A SEAM. Each is an operating system's own call - on Windows the time of the last input, a
# process created outside the scheduler's job, a close message posted to a window - and the
# supervisor's rules must not change when the system does. So the rules ask this port, and an adapter
# under platform/<name>/Services.ps1 answers, registering itself when it is dot-sourced, as
# platform/<name>/Firewall.ps1 registers with core/FirewallPort.ps1. A new system is a new file there.
#
# EVERY ANSWER IS A core/Tristate.ps1 ANSWER, AND UNKNOWN IS THE DEFAULT. With no adapter for this
# system, or one that throws, or one that answers with something that is not an answer, the port says
# unknown and why. The supervisor reads an unknown idleness as "wait" - it never restarts a service
# under a person it cannot see - and an unknown start as a failed start.
#
#   IdleSeconds  {}                          -> known whole seconds since the person's last input;
#                                               unknown when this process cannot see their input
#   Start        { param($Launch) }          -> known { pid; startedAt } of the process it made
#   CloseWindow  { param($ProcessId, $Handle) } -> known "asked" when the window is that process's
#                                               and was asked to close; absent when there is no such
#                                               window of that process; unknown otherwise. OPTIONAL: an
#                                               adapter without it cannot close a window, and says so.
#
# THE LAUNCH (New-HordeServiceLaunch) is the start, as data, in the one shape every adapter takes:
#   kind horde    script (a checkout's horde entry point), words, named, switches, environment,
#                 workingDirectory, logFile (where what it prints is kept)
#   kind program  program, arguments, workingDirectory
# How a value reaches the program - which shell, which quoting - is the adapter's business, and no
# value is ever parsed as code on the way (core/schedule/WindowsTaskScheduler.ps1 holds the same rule
# for a scheduled job, from the review of PR #70).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Tristate.ps1")

if ($null -eq (Get-Variable -Name HordeServiceHosts -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeServiceHosts = New-Object System.Collections.ArrayList }

function Register-HordeServiceHost {
    # Called by platform/<name>/Services.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Applies,
        [Parameter(Mandatory = $true)][scriptblock]$IdleSeconds,
        [Parameter(Mandatory = $true)][scriptblock]$Start,
        [scriptblock]$CloseWindow = $null
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a platform name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($known in @($script:HordeServiceHosts)) { if ($known.name -ceq $Name) { $script:HordeServiceHosts.Remove($known) } }
    [void]$script:HordeServiceHosts.Add([pscustomobject]@{ PSTypeName = "Horde.ServiceHost"; name = $Name; applies = $Applies; idleSeconds = $IdleSeconds; start = $Start; closeWindow = $CloseWindow })
}

function Get-HordeServiceHostFiles {
    # The adapter files, found by folder: platform/<name>/Services.ps1, for the caller to dot-source
    # at its own scope, so the helpers an adapter defines stay visible to the blocks it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $platforms = Join-Path $Root "platform"
    if (-not (Test-Path -LiteralPath $platforms -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $platforms -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Services.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeServiceHost {
    # The adapter for this system, as an answer: the first registered one whose Applies is exactly true.
    if ($script:HordeServiceHosts.Count -eq 0) { return (New-HordeUnknown -Reason "no service host adapter is loaded for this system") }
    foreach ($a in @($script:HordeServiceHosts)) {
        $here = $null
        try { $here = @(& $a.applies) | Select-Object -Last 1 } catch { continue }
        if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $a) }
    }
    return (New-HordeUnknown -Reason "no service host adapter is for this system")
}

function New-HordeServiceLaunch {
    # The launch of a service, as data (the header). Checked here once, so every adapter is handed the
    # same thing: names that are names, texts on one line, absolute paths.
    param(
        [Parameter(Mandatory = $true)][ValidateSet("horde", "program")][string]$Kind,
        [string]$Script = "", [string[]]$Words = @(), $Named = $null, [string[]]$Switches = @(), [hashtable]$Environment = @{},
        [string]$Program = "", [string[]]$Arguments = @(), [string]$WorkingDirectory = "", [string]$LogFile = ""
    )
    $table = [ordered]@{}
    if ($null -ne $Named) { foreach ($k in @($Named.Keys)) { $table["" + $k] = "" + $Named[$k] } }
    foreach ($n in @(@($table.Keys) + @($Switches))) { if ("" + $n -cnotmatch '\A[A-Za-z][A-Za-z0-9]{0,39}\z') { throw ("not a parameter name: '" + $n + "'") } }
    foreach ($k in @($Environment.Keys)) { if ("" + $k -cnotmatch '\A[A-Z_][A-Z0-9_]*\z') { throw ("not an environment variable name: '" + $k + "'") } }
    foreach ($w in @($Words)) { if ("" + $w -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { throw ("not a word of a horde command: '" + $w + "'") } }
    foreach ($v in @(@($Script, $Program, $WorkingDirectory, $LogFile) + @($Arguments) + @($table.Values) + @($Environment.Values))) { if ("" + $v -match '\p{Cc}') { throw "a launch's values cannot hold a line break or any other control character" } }
    if ($Kind -ceq "horde") {
        if (-not [System.IO.Path]::IsPathRooted($Script) -or @($Words).Count -lt 1) { throw "a horde launch names the absolute path of a horde entry point and at least one word" }
        if ($LogFile -ne "" -and -not [System.IO.Path]::IsPathRooted($LogFile)) { throw "a launch's log file is an absolute path" }
    } elseif (-not [System.IO.Path]::IsPathRooted($Program)) { throw "a program launch names the absolute path of a program" }
    if ($WorkingDirectory -ne "" -and -not [System.IO.Path]::IsPathRooted($WorkingDirectory)) { throw "a launch's working directory is an absolute path" }
    return [pscustomobject]@{ PSTypeName = "Horde.ServiceLaunch"; kind = $Kind; script = $Script; words = [string[]]@($Words); named = $table; switches = [string[]]@($Switches); environment = $Environment
        program = $Program; arguments = [string[]]@($Arguments); workingDirectory = $WorkingDirectory; logFile = $LogFile }
}

function ConvertTo-HordeServiceArgument {
    # One argument as a command line carries it, so that the program reads back exactly this text:
    # quoted when it is empty or holds a space, a tab or a quote; a quote escaped with a backslash; and
    # backslashes doubled only where they stand before a quote, or before the closing quote. These are
    # the rules the C runtime splits a command line by, and the rules .NET's own process start reads
    # its one argument string by on every system, so the function is the port's and not one adapter's.
    # NOT a shell's quoting: nothing made here is ever handed to a shell to parse.
    param([AllowEmptyString()][string]$Text)
    if ($Text.Length -gt 0 -and $Text -notmatch '[\s"]') { return $Text }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($c in $Text.ToCharArray()) {
        if ($c -eq '\') { $slashes++; continue }
        if ($c -eq '"') { [void]$sb.Append([char]92, (2 * $slashes + 1)); [void]$sb.Append('"'); $slashes = 0; continue }
        if ($slashes -gt 0) { [void]$sb.Append([char]92, $slashes); $slashes = 0 }
        [void]$sb.Append($c)
    }
    if ($slashes -gt 0) { [void]$sb.Append([char]92, (2 * $slashes)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-HordeServiceHostBlock {
    # Run one block of the adapter and hold its answer to the port's rule: a core/Tristate.ps1 answer,
    # or unknown with the reason. -Allowed is which states the block may answer.
    param([Parameter(Mandatory = $true)][string]$What, $Block, [object[]]$With = @(), [string[]]$Allowed = @("known", "unknown"))
    $found = Get-HordeServiceHost
    if ($found.state -cne "known") { return (New-HordeUnknown -Reason ($What + ": " + $found.reason)) }
    $run = $found.value.$Block
    if ($null -eq $run) { return (New-HordeUnknown -Reason ($What + ": the " + $found.value.name + " adapter cannot do that")) }
    $answer = $null
    try { $answer = @(& $run @With) | Select-Object -Last 1 } catch { return (New-HordeUnknown -Reason ($What + ": the " + $found.value.name + " adapter failed") -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $answer) -or $Allowed -cnotcontains $answer.state) { return (New-HordeUnknown -Reason ($What + ": the " + $found.value.name + " adapter did not answer")) }
    return $answer
}

function Get-HordePersonIdleSeconds {
    # How long since the person last touched this machine: known whole seconds, never less than 0;
    # unknown when it cannot be told. UNKNOWN IS NEVER IDLE: the one caller that restarts something
    # on this answer waits on an unknown.
    $answer = Invoke-HordeServiceHostBlock -What "whether the person is idle" -Block "idleSeconds"
    if ($answer.state -cne "known") { return $answer }
    if (($answer.value -isnot [int] -and $answer.value -isnot [long]) -or $answer.value -lt 0) { return (New-HordeUnknown -Reason "whether the person is idle: the adapter answered something that is not a number of seconds") }
    return (New-HordeKnown -Value ([long]$answer.value))
}

function Start-HordeServiceProcess {
    # Start what -Launch describes as a process that outlives this one: known { pid; startedAt (UTC) },
    # or unknown with the reason. A known answer without both is not one: the pair is the identity the
    # supervisor later stops by (core/Heartbeat.ps1).
    param([Parameter(Mandatory = $true)]$Launch)
    if ($null -eq $Launch -or @($Launch.PSObject.TypeNames) -notcontains "Horde.ServiceLaunch") { throw "-Launch must be made by New-HordeServiceLaunch" }
    $answer = Invoke-HordeServiceHostBlock -What "the start" -Block "start" -With @(, $Launch)
    if ($answer.state -cne "known") { return $answer }
    $v = $answer.value
    if ($v -isnot [System.Management.Automation.PSCustomObject] -or $null -eq $v.PSObject.Properties["pid"] -or $null -eq $v.PSObject.Properties["startedAt"] -or ($v.pid -isnot [int] -and $v.pid -isnot [long]) -or $v.pid -le 0 -or $v.startedAt -isnot [datetime]) {
        return (New-HordeUnknown -Reason "the start: the adapter did not say which process it made and when it started")
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ pid = [int]$v.pid; startedAt = $v.startedAt.ToUniversalTime() }))
}

function Close-HordeServiceWindow {
    # Ask the window -Handle of process -ProcessId to close, as a person clicking its close button
    # would: known "asked", absent (that process has no such window: nothing was sent), or unknown.
    # The adapter must check that the window is that process's BEFORE it sends anything: a handle read
    # from a file may have been given to another program's window since.
    param([Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][long]$Handle)
    if ($ProcessId -le 0 -or $Handle -le 0) { return (New-HordeUnknown -Reason "closing its window: no process and window were named") }
    return (Invoke-HordeServiceHostBlock -What "closing its window" -Block "closeWindow" -With @($ProcessId, $Handle) -Allowed @("known", "absent", "unknown"))
}
