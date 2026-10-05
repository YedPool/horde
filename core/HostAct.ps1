# core/HostAct - the acting port of a terminal host: how a node starts, types into, checks and ends a
# pane of its own terminal without naming the terminal.
#
# THE ACT PATH'S A2 (planning/execution-plan-remote.md, R19's first version, 2026-10-05). The read half
# of a host is core/HostPort.ps1; this is the half that acts, kept apart so a reader can never act. One
# adapter per host, hosts/<name>/Act.ps1, registers itself here when it is dot-sourced, as the agent
# adapters do (core/Transcript.ps1, core/AgentLaunch.ps1), and is found by folder, never by name
# (CONTRIBUTING 14). An actor gives five blocks, each answering in core/tristate form:
#   Resolve ($name)               the full path of a program from its command name
#   Start   ($program, $argv, $cwd)  a new pane running it: known { handle; program; cwd }
#   Send    ($handle, $text)      typed into that pane: known $true
#   Live    ($handle)             whether the pane is still there: known bool, unknown if unlisted
#   Stop    ($handle)             the pane ended by the terminal: known $true
# A handle is the host's own text, opaque here (core/HostPort.ps1: "a host handle ... never a key").
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

$script:HordeHostActors = New-Object System.Collections.ArrayList

function Register-HordeHostActor {
    # Called by hosts/<name>/Act.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Resolve,
        [Parameter(Mandatory = $true)][scriptblock]$Start,
        [Parameter(Mandatory = $true)][scriptblock]$Send,
        [Parameter(Mandatory = $true)][scriptblock]$Live,
        [Parameter(Mandatory = $true)][scriptblock]$Stop
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a host name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($a in $script:HordeHostActors) { if ($a.name -ceq $Name) { $script:HordeHostActors.Remove($a); break } }
    [void]$script:HordeHostActors.Add([pscustomobject]@{ name = $Name; resolve = $Resolve; start = $Start; send = $Send; live = $Live; stop = $Stop })
}

function Get-HordeHostActor {
    # The actor registered for one host, as an answer.
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($a in $script:HordeHostActors) { if ($a.name -ceq $Name) { return (New-HordeKnown -Value $a) } }
    return (New-HordeUnknown -Reason ("no acting adapter is loaded for the host " + $Name))
}

function Get-HordeHostActorFiles {
    # The acting adapter files, found by folder: hosts/<name>/Act.ps1. The CALLER dot-sources each at
    # its own scope, so the adapter's helpers stay visible to the blocks it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $hosts = Join-Path $Root "hosts"
    if (-not (Test-Path -LiteralPath $hosts -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $hosts -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Act.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}
