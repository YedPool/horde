# core/HostAct - the acting port of a terminal host: how a node starts, types into, checks and ends a
# pane of its own terminal without naming the terminal.
#
# THE ACT PATH'S A2 (planning/execution-plan-remote.md, R19's first version, 2026-10-05). The read half
# of a host is core/HostPort.ps1; this is the half that acts, kept apart so a reader can never act. One
# adapter per host, hosts/<name>/Act.ps1, registers itself here when it is dot-sourced, as the agent
# adapters do (core/Transcript.ps1, core/AgentLaunch.ps1), and is found by folder, never by name
# (CONTRIBUTING 14). An actor gives six blocks, each answering in core/tristate form. Every one that
# touches the terminal takes a $target: the terminal is always named, never left to the environment
# (review of PR #96).
#   Own     ()                    this node's own terminal, named explicitly: known target, or unknown
#                                 when which one it is cannot be told. A node calls it with no
#                                 arguments. The isolation probe passes two: ($profileDir, $running),
#                                 a profile folder to look in instead of the user's, and the terminals
#                                 to take as running ({ pid; start } each) instead of those listed now.
#   OwnMarker ($profileDir, $pid) optional: the file whose presence makes terminal $pid that profile's
#                                 own - where the probe's control plants one to show Own can see it.
#   Resolve ($name)               the full path of a program from its command name
#   Start   ($target, $program, $argv, $cwd, $environment)  a new pane running it: known { handle;
#                                 program; cwd }. $environment maps a name to the value the session
#                                 gets, or to $null for a variable of the node it must not inherit.
#   Send    ($target, $handle, $text, $submit)  printable text typed into that pane, then Enter when
#                                 $submit: known $true
#   Live    ($target, $handle, $expect)  whether the pane is still there running the expected process
#                                 { pid; procStart }: known bool, unknown when it cannot be told
#   Stop    ($target, $handle, $expect)  the pane ended, only after the expected process is proven
#                                 to be in it: known $true
# A handle is the host's own text, opaque here (core/HostPort.ps1: "a host handle ... never a key"); a
# host whose pane ids restart puts its terminal's identity in it.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

# A REGISTRY IS MADE ONCE, never reset by a later load (review of #114): core files load what they
# call, so this file is dot-sourced again by files loaded after the adapters have registered, and an
# unconditional reset here would silently empty it.
if ($null -eq (Get-Variable -Name HordeHostActors -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeHostActors = New-Object System.Collections.ArrayList }

function Register-HordeHostActor {
    # Called by hosts/<name>/Act.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Own,
        [Parameter(Mandatory = $true)][scriptblock]$Resolve,
        [Parameter(Mandatory = $true)][scriptblock]$Start,
        [Parameter(Mandatory = $true)][scriptblock]$Send,
        [Parameter(Mandatory = $true)][scriptblock]$Live,
        [Parameter(Mandatory = $true)][scriptblock]$Stop,
        [scriptblock]$OwnMarker = $null
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a host name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($a in $script:HordeHostActors) { if ($a.name -ceq $Name) { $script:HordeHostActors.Remove($a); break } }
    [void]$script:HordeHostActors.Add([pscustomobject]@{ name = $Name; own = $Own; resolve = $Resolve; start = $Start; send = $Send; live = $Live; stop = $Stop; ownMarker = $OwnMarker })
}

function Get-HordeHostActor {
    # The actor registered for one host, as an answer.
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($a in $script:HordeHostActors) { if ($a.name -ceq $Name) { return (New-HordeKnown -Value $a) } }
    return (New-HordeUnknown -Reason ("no acting adapter is loaded for the host " + $Name))
}

function Get-HordeHostActors {
    # Every registered actor: what a check over all hosts, such as a node's isolation probe, walks.
    return @($script:HordeHostActors)
}

function Get-HordeHostActorFiles {
    # The acting adapter files, found by folder: hosts/<name>/Act.ps1. The CALLER dot-sources each at
    # its own scope, so the adapter's helpers stay visible to the blocks it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $hosts = Join-Path $Root "hosts"
    if (-not (Test-Path -LiteralPath $hosts -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $hosts -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Act.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}
