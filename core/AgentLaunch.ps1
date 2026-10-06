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
#   CloseText      the text typed into the session's pane, in order, that ends it gracefully. The
#                  host types it; the caller then proves the process gone by pid and start time, and
#                  ends the pane itself if it is not (a session showing a dialog does not read it).
#
# THE PROGRAM IS AN ABSOLUTE .EXE, NEVER A NAME LOOKED UP AT SPAWN TIME, NEVER A SCRIPT SHIM (review
# of PR #98, F3). A .cmd or .bat is run by cmd.exe, which re-parses the whole command line, so a prompt
# or name holding " & ^ % | would become commands (the BatBadBut class); and on a machine where npm
# put a harness's .cmd shim ahead of its .exe on PATH, a lookup at spawn time would pick the shim. So the plan
# takes the host's -Resolve (name -> full path) and accepts only a rooted path ending in .exe; the host
# runs that path as given. As a second line, cmd metacharacters never reach a session's name.
#
# THE LEVEL IS THE POLICY'S DECISION (F4). The plan takes Test-HordeRemotePolicy's decision itself, and
# refuses unless it is allowed, so no caller can hand it a level the policy did not admit.
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
        [Parameter(Mandatory = $true)][scriptblock]$ReadMode,
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowEmptyCollection()][string[]]$CloseText
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("an adapter name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    if ($Program -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { throw ("a launch adapter names its program by command name, never a path: '" + $Program + "'") }
    foreach ($a in $script:HordeLaunchAdapters) { if ($a.name -ceq $Name) { $script:HordeLaunchAdapters.Remove($a); break } }
    if (@($CloseText | Where-Object { "" + $_ -ne "" }).Count -eq 0) { throw ("the adapter " + $Name + " gives no text that ends its session") }
    [void]$script:HordeLaunchAdapters.Add([pscustomobject]@{ name = $Name; program = $Program; argv = $Argv; preconditions = $Preconditions; identify = $Identify; readMode = $ReadMode; closeText = [string[]]@($CloseText) })
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
        $t = ([regex]::Replace("" + $Title, '[^\x21-\x7E]+', " "))
        # cmd.exe's metacharacters never reach a name, though no shell should ever see it (F3).
        $t = ([regex]::Replace($t, '["&|^%<>!`]+', " "))
        $t = ([regex]::Replace($t, ' +', " ")).Trim()
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

function Test-HordeLaunchProgramPath {
    # Is -Path a full, local, absolute path to an .exe? A drive letter, ":\", and the path equal to its
    # own full form: C:tool.exe (drive-relative) and \tool.exe (rooted on the current drive) are
    # rooted to IsPathRooted but name a file relative to state the node does not control (re-review of
    # PR #98).
    param([AllowEmptyString()][string]$Path)
    if ($Path -cnotmatch '\A[A-Za-z]:\\') { return $false }
    if ([System.IO.Path]::GetExtension($Path) -ine ".exe") { return $false }
    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $false }
    return [bool]($full -ceq $Path)
}

function New-HordeLaunchPlan {
    # The launch plan for one session, as an answer: known { harness; program; argv; level; model;
    # name; notes }, or unknown with the first reason it cannot be built. Pure but for what the
    # adapter's Preconditions block reads, which is read-only.
    # -Resolution: Resolve-HordeEngine's. -Decision: Test-HordeRemotePolicy's, whose level is used and
    # which must be allowed. -SessionId: the id the node chose. -Name: Format-HordeSessionName's answer.
    # -Prompt: the first prompt's text, or "". -Resolve: the host's program lookup, name -> answer.
    param([Parameter(Mandatory = $true)]$Resolution, [Parameter(Mandatory = $true)]$Decision,
        [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)]$Name,
        [AllowEmptyString()][string]$Prompt = "", [Parameter(Mandatory = $true)][scriptblock]$Resolve, $Levels = $null)
    if (-not ($Decision.allowed -is [bool] -and $Decision.allowed)) { return (New-HordeUnknown -Reason ("the node's policy did not allow this session: " + (@($Decision.reasons) -join "; "))) }
    $Level = "" + $Decision.level
    if ($Level -eq "") { return (New-HordeUnknown -Reason "the policy's decision names no level") }
    if ($Resolution.binding.state -ne "known") { return (New-HordeUnknown -Reason ("the engine is not resolved: " + $Resolution.binding.reason)) }
    $b = $Resolution.binding.value
    $d = $Resolution.descriptor
    if ($null -eq $d) { return (New-HordeUnknown -Reason ("the harness " + $b.harness + " has no descriptor")) }
    $ad = Get-HordeLaunchAdapter -Name ("" + $b.harness)
    if ($ad.state -ne "known") { return $ad }
    $a = $ad.value
    $pattern = "" + (Get-HordeAgentProp $d "sessionIdPattern")
    if ($SessionId -cnotmatch $pattern -or $SessionId -cmatch '[\r\n]') { return (New-HordeUnknown -Reason ("'" + $SessionId + "' is not a session id the harness " + $b.harness + " takes")) }

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
    $prog = & $Resolve $a.program
    if ($null -eq $prog -or $prog.state -ne "known") {
        $why = "the host could not find the program " + $a.program
        if ($null -ne $prog) { $why = "" + $prog.reason }
        return (New-HordeUnknown -Reason $why)
    }
    $path = "" + $prog.value
    if (-not (Test-HordeLaunchProgramPath -Path $path)) { return (New-HordeUnknown -Reason ("the program must be an absolute path to an .exe, never a name looked up at spawn time or a script shim run by cmd.exe; the host gave '" + $path + "'")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ harness = "" + $b.harness; program = $path; argv = [string[]]@($argv.value); level = $Level; model = $b.model; name = $nameText; notes = $notes.ToArray() }))
}
