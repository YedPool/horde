# fleet/Port.ps1 - the two adapters hibernation needs, found by folder and never by name.
#
# Hibernation (fleet/Hibernation.ps1, fleet/Wake.ps1) speaks of sessions, windows, tabs and panes. Which
# harness runs a session and which terminal shows it are the adapters' to say (CONTRIBUTING 14), so each
# registers here when its file is dot-sourced, as the launch and acting adapters do
# (core/AgentLaunch.ps1, core/HostAct.ps1):
#
#   agents/<name>/Fleet.ps1  Register-HordeFleetAgent
#     Snapshot   ()                          one fresh reading of which of its sessions run now (opaque)
#     Verdict    ($snapshot, $id, $cwd, $ignore, $since, $process)  { state: running | stopped | unknown;
#                                            kind; reason; pid }; $ignore: ids that cannot be the session
#                                            under a new id; $process: the session's own process as recorded,
#                                            { pid; start } or $null - that process running under any id is
#                                            the session running; $since: a [datetime] or $null - another
#                                            process that began at or before it cannot be the session under
#                                            a new id (used only with $process)
#     Running    ($snapshot)                 the live ones, { sessionId; pid; cwd; start } each
#     ResumeLine ($id)                       the one shell line that resumes session $id
#     Scrub      ()                          environment map for the woken pane: name -> $null removes it
#     LastTyped  ($transcriptPath, $since)   OPTIONAL (hibernate, slice 2): the turns a person typed into
#                                            the session at or after $since, as an answer: known list of
#                                            { at (UTC [datetime]); text (its first 200 characters) },
#                                            newest first; unknown when the transcript cannot be read. A
#                                            line the fleet's own tools typed (a mail pointer) may be
#                                            among them: telling those apart is fleet/Hibernate.ps1's
#   hosts/<name>/Fleet.ps1   Register-HordeFleetHost
#     Placement  ($refs)                     where each session sits now: $refs are { sessionId; instance;
#                                            pane } as the fleet registry stores them; answer known map
#                                            sessionId -> { windowKey; tabIndex; left; top; cols; rows;
#                                            tabCols; tabRows }, a session it cannot place left out
#     Open       ()                          the terminal a wake spawns into, as an answer: known
#                                            { spawn; paneOf; describe }, each a script block bound to it
#                                            spawn ($request) -> answer known { pane; window }; ABSENT only
#                                              when the request was refused before any call to the terminal
#                                              (nothing started); any other answer that is not known (a
#                                              timeout, a failed call) means a pane MAY have started, and
#                                              the wake holds the session until -Retry; where
#                                              $request is { mode: window | tab | split; cwd; line;
#                                              environment; window; pane; direction: right | bottom;
#                                              percent }
#                                            paneOf ($pid) -> answer known pane id of that process
#     Describe   ($request)                  the exact command a spawn would run, as text, for -DryRun
#     Release    ($sessionId)                optional: remove the terminal restore's "do not restore" marker
#                                            of that one session, as an answer: known "removed" or "none",
#                                            unknown with the reason. A wake calls it just before the
#                                            session's spawn, after its last liveness check.
#     Mark       ($sessionId, $reason, $at)  optional: write the terminal restore's "do not restore" marker of
#                                            that one session (reason parked or hibernated, at the UTC time
#                                            it was put to sleep), whole, as an answer: known (where) or
#                                            unknown with the reason. Hibernate calls it for each session it
#                                            parks, once its process is gone; the Release above is its pair.
#
# ONE OF EACH. The fleet registry holds one harness's sessions and one terminal's panes; when more than
# one adapter of a kind is loaded, which one a session belongs to cannot be told from the record, so
# Resolve-HordeFleetAdapter refuses rather than choose (core/SessionSeat.ps1 holds the same rule for two
# holders of a role).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")

# A REGISTRY IS MADE ONCE, never reset by a later load (review of #114, core/HostAct.ps1): adapters
# dot-source this file themselves, so a reset here would empty what an earlier adapter registered.
if ($null -eq (Get-Variable -Name HordeFleetAgents -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeFleetAgents = New-Object System.Collections.ArrayList }
if ($null -eq (Get-Variable -Name HordeFleetHosts -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeFleetHosts = New-Object System.Collections.ArrayList }

function Register-HordeFleetAgent {
    # Called by agents/<name>/Fleet.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Snapshot,
        [Parameter(Mandatory = $true)][scriptblock]$Verdict,
        [Parameter(Mandatory = $true)][scriptblock]$Running,
        [Parameter(Mandatory = $true)][scriptblock]$ResumeLine,
        [Parameter(Mandatory = $true)][scriptblock]$Scrub,
        [scriptblock]$LastTyped = $null
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("an adapter name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($a in @($script:HordeFleetAgents)) { if ($a.name -ceq $Name) { $script:HordeFleetAgents.Remove($a) } }
    [void]$script:HordeFleetAgents.Add([pscustomobject]@{ name = $Name; snapshot = $Snapshot; verdict = $Verdict; running = $Running; resumeLine = $ResumeLine; scrub = $Scrub; lastTyped = $LastTyped })
}

function Register-HordeFleetHost {
    # Called by hosts/<name>/Fleet.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Placement,
        [Parameter(Mandatory = $true)][scriptblock]$Open,
        [Parameter(Mandatory = $true)][scriptblock]$Describe,
        [scriptblock]$Release = $null,
        [scriptblock]$Mark = $null
    )
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("an adapter name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($h in @($script:HordeFleetHosts)) { if ($h.name -ceq $Name) { $script:HordeFleetHosts.Remove($h) } }
    [void]$script:HordeFleetHosts.Add([pscustomobject]@{ name = $Name; placement = $Placement; open = $Open; describe = $Describe; release = $Release; mark = $Mark })
}

function Resolve-HordeFleetAdapter {
    # The one loaded adapter of -Kind (agent or host), as an answer: unknown when none is loaded or when
    # more than one is, naming them.
    param([Parameter(Mandatory = $true)][ValidateSet("agent", "host")][string]$Kind)
    $list = @($script:HordeFleetAgents)
    if ($Kind -ceq "host") { $list = @($script:HordeFleetHosts) }
    if ($list.Count -eq 1) { return (New-HordeKnown -Value $list[0]) }
    if ($list.Count -eq 0) { return (New-HordeUnknown -Reason ("no fleet " + $Kind + " adapter is loaded, so hibernation cannot tell " + $(if ($Kind -ceq "agent") { "which sessions run" } else { "where sessions sit" }))) }
    return (New-HordeUnknown -Reason ("" + $list.Count + " fleet " + $Kind + " adapters are loaded (" + (@($list | ForEach-Object { $_.name }) -join ", ") + "); which one the fleet registry's sessions belong to cannot be told, so none is chosen"))
}

function Get-HordeFleetAdapterFiles {
    # The adapter files, found by folder: agents/<name>/Fleet.ps1 and hosts/<name>/Fleet.ps1. The CALLER
    # dot-sources each at its own scope, so the adapter's helpers stay visible to the blocks it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $out = New-Object System.Collections.ArrayList
    foreach ($family in @("agents", "hosts")) {
        $dir = Join-Path $Root $family
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name)) {
            $f = Join-Path $d.FullName "Fleet.ps1"
            if (Test-Path -LiteralPath $f -PathType Leaf) { [void]$out.Add($f) }
        }
    }
    return @($out)
}
