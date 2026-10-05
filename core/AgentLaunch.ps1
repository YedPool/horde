# core/AgentLaunch - the launch port: what a harness is started with, decided before anything starts.
#
# REMOTE PLAN STEP R9 AND ENGINES E9, cut to the act path (decision of 2026-10-05). A node about to
# start a session asks this file for a LAUNCH PLAN: the program's command name and its argv, built
# from the resolved engine (core/EngineResolve.ps1), the requested permission level, the session id
# the node chose, the session's name and its first prompt. Nothing here starts a process: starting
# belongs to the host layer (hosts/<name>/), which runs the plan in a pane of its own terminal.
#
# ONE ADAPTER PER HARNESS, found by folder and never named (CONTRIBUTING 14): agents/<name>/Launch.ps1
# registers itself with Register-HordeLaunchAdapter, as the transcript adapters do. An adapter gives:
#   Program        the command the host runs, a name looked up on the node's PATH, never a path.
#   Argv           { sessionId; permissionArgs; model; name; prompt } -> the argv, as an answer.
#   Preconditions  ($names) -> the names it VERIFIED against the real environment, read-only (issue
#                  #67, item 1). A name it cannot check is not returned, so the level is refused.
#   Identify       ($sessionId, $environment) -> the started process as the harness records it:
#                  known { pid; procStart; remoteControl; name }, absent before it has written
#                  anything. $environment is the hashtable of variables the HARNESS sees, from which
#                  the adapter finds its own files; never this process's environment, which a pane
#                  does not inherit (measured 2026-10-05).
#   ReadMode       ($sessionId, $environment) -> the level the running session reports it is in
#                  (issue #67, item 2), as an answer; unknown or absent when it cannot be read, which
#                  the caller treats as refused (decision 6 of 2026-10-05: fail closed).
#
# THE NAME. Decision of 2026-10-05: label plus run title, as the web session names technique has it
# (engines group I), capped. Format-HordeSessionName is the one place it is made; an adapter is
# handed the name and never formats one. A harness whose session.remoteName capability is not yes gets
# no name in its argv, and the plan says why.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "AgentDescriptor.ps1")
. (Join-Path $PSScriptRoot "PermissionLevels.ps1")

$script:HordeLaunchAdapters = New-Object System.Collections.ArrayList
# The longest session name. The web list shows about 60 characters before it cuts a title, measured on
# the web session list on 2026-10-01 with the fleet's own titles; a name past that loses its end anyway.
$script:HordeSessionNameMax = 60
$script:HordeLabelPattern = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'

function Register-HordeLaunchAdapter {
    # Called by an adapter file when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(Mandatory = $true)][scriptblock]$Argv,
        [Parameter(Mandatory = $true)][scriptblock]$Preconditions,
        [Parameter(Mandatory = $true)][scriptblock]$Identify,
        [Parameter(Mandatory = $true)][scriptblock]$ReadMode
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("an adapter name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    if ($Program -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { throw ("a launch adapter names its program by command name, never a path: '" + $Program + "'") }
    foreach ($a in $script:HordeLaunchAdapters) { if ($a.name -ceq $Name) { $script:HordeLaunchAdapters.Remove($a); break } }
    [void]$script:HordeLaunchAdapters.Add([pscustomobject]@{ name = $Name; program = $Program; argv = $Argv; preconditions = $Preconditions; identify = $Identify; readMode = $ReadMode })
}

function Get-HordeLaunchAdapter {
    # The adapter registered for one harness, as an answer.
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($a in $script:HordeLaunchAdapters) { if ($a.name -ceq $Name) { return (New-HordeKnown -Value $a) } }
    return (New-HordeUnknown -Reason ("no launch adapter is loaded for the harness " + $Name + ", so Horde cannot start it"))
}

function Get-HordeLaunchAdapterFiles {
    # The adapter files, found by folder: agents/<name>/Launch.ps1. The CALLER dot-sources each at its
    # own scope, so the adapter's helpers stay visible to the blocks it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Launch.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Format-HordeSessionName {
    # The session's name: its label, then its run title, as one line of printable ASCII, at most
    # $script:HordeSessionNameMax characters, cut at a word where it must be cut. Answers unknown when
    # the label is not a label: a name with no label could collide with another session's.
    param($Label, $Title = $null, [int]$Max = $script:HordeSessionNameMax)
    if ($Label -isnot [string] -or $Label -cnotmatch $script:HordeLabelPattern) { return (New-HordeUnknown -Reason ("'" + $Label + "' is not a session label, so the session gets no name")) }
    $t = ""
    if ($null -ne $Title) {
        # Every character outside printable ASCII becomes a space, and runs of spaces become one.
        $t = ([regex]::Replace("" + $Title, '[^\x21-\x7E]+', " ")).Trim()
    }
    $name = $Label
    if ($t -ne "") { $name = $Label + " " + $t }
    if ($name.Length -gt $Max) {
        $cut = $name.Substring(0, $Max)
        $sp = $cut.LastIndexOf(" ")
        if ($sp -gt $Label.Length) { $cut = $cut.Substring(0, $sp) }
        $name = $cut.TrimEnd()
    }
    return (New-HordeKnown -Value $name)
}

function New-HordeLaunchPlan {
    # The launch plan for one session, as an answer: known { harness; program; argv; level; model;
    # name; notes }, or unknown with the first reason it cannot be built. Pure but for what the
    # adapter's Preconditions block reads, which is read-only.
    # -Resolution: Resolve-HordeEngine's. -Level: the permission level already admitted by
    # Test-HordeRemotePolicy. -SessionId: the id the node chose. -Name: Format-HordeSessionName's
    # answer. -Prompt: the first prompt's text, or "".
    param([Parameter(Mandatory = $true)]$Resolution, [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)]$Name,
        [AllowEmptyString()][string]$Prompt = "", $Levels = $null)
    if ($Resolution.binding.state -ne "known") { return (New-HordeUnknown -Reason ("the engine is not resolved: " + $Resolution.binding.reason)) }
    $b = $Resolution.binding.value
    $d = $Resolution.descriptor
    if ($null -eq $d) { return (New-HordeUnknown -Reason ("the harness " + $b.harness + " has no descriptor")) }
    $ad = Get-HordeLaunchAdapter -Name ("" + $b.harness)
    if ($ad.state -ne "known") { return $ad }
    $a = $ad.value
    $pattern = "" + (Get-HordeAgentProp $d "sessionIdPattern")
    if ($SessionId -cnotmatch $pattern) { return (New-HordeUnknown -Reason ("'" + $SessionId + "' is not a session id the harness " + $b.harness + " takes")) }

    # PRECONDITIONS ARE VERIFIED, NOT CLAIMED (issue #67, item 1). The level's row names what must hold;
    # the adapter checks each against the real environment and returns only what it saw hold.
    $rows = Get-HordeAgentProp $d "permissionLevels"
    $row = @(@($rows) | Where-Object { (Get-HordeAgentProp $_ "level") -ceq $Level })
    $need = @()
    if ($row.Count -eq 1) { $need = @(@(Get-HordeAgentProp $row[0] "preconditions") | Where-Object { $null -ne $_ } | ForEach-Object { "" + $_.name }) }
    $verified = @()
    if ($need.Count -gt 0) { $verified = @(& $a.preconditions $need | ForEach-Object { "" + $_ } | Where-Object { $need -ccontains $_ }) }
    $perm = Get-HordePermissionArgs -Descriptor $d -Level $Level -EntryPoint "interactive" -Verified $verified -Levels $Levels
    if ($perm.state -ne "known") { return (New-HordeUnknown -Reason $perm.reason) }

    $notes = New-Object System.Collections.ArrayList
    $nameText = ""
    if ($Name.state -ne "known") { [void]$notes.Add("unnamed: " + $Name.reason) }
    elseif (-not (Test-HordeAgentCapability -Descriptor $d -Name "session.remoteName")) { [void]$notes.Add("unnamed: the harness " + $b.harness + " cannot be told a remote session name (session.remoteName is not yes)") }
    else { $nameText = "" + $Name.value }

    $spec = [pscustomobject]@{ sessionId = $SessionId; permissionArgs = @($perm.value); model = $b.model; name = $nameText; prompt = $Prompt }
    $argv = & $a.argv $spec
    if ($null -eq $argv -or $argv.state -ne "known") {
        $why = "the adapter built no argv"
        if ($null -ne $argv) { $why = $argv.reason }
        return (New-HordeUnknown -Reason $why)
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ harness = "" + $b.harness; program = $a.program; argv = [string[]]@($argv.value); level = $Level; model = $b.model; name = $nameText; notes = $notes.ToArray() }))
}
