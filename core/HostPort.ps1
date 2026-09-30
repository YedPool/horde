# core/HostPort - the one way the read model learns what a terminal host can see right now.
#
# D12 (planning/migration-plan.html): nothing outside hosts/<name>/ names a terminal. The
# projection needs two live facts that only a host can give - which handles (panes, in the first
# host's words) exist, and which host instance they belong to - so it asks through this port and
# never through a terminal's own command line. The first real adapter will live under
# hosts/<name>/; until then tests pass a fake port and the reality check passes an unavailable one.
#
# WHAT A PORT ANSWERS, both through core/tristate so "could not ask" is never read as "none":
#   Handles   the live handles, each { handle; window; tab; hostTitle } - handle and window as
#             text, because a handle is opaque to the engine (D12: a terminal's pane id "is a host
#             handle ... never a key"). wezfleet turned an unreadable pane list into an empty map
#             (YedPool/wezfleet lib/Common.ps1:497-503) and census then printed "no live panes."
#             for a mux it could not read (commands/census.ps1:10-11). Here that is unknown.
#   Instance  { id; startedAt; running; ambiguous }: which host instance the handles belong to,
#             when it started (a record written before then describes another instance's
#             handle - YedPool/wezfleet 0e1c75a), how many instances are running, and whether
#             the port cannot tell which one is meant. wezfleet's Get-WfCurrentInstance had the
#             same four facts (lib/Common.ps1:539-595).
#
# A port is data plus two script blocks. The projection calls them through Invoke-HordeRead, so a
# port that throws, writes an error or returns nothing is unknown with the reason, never empty.

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

function New-HordeHostPort {
    # A host port. -Name is the host's own name, supplied by its adapter; core never spells one.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Handles,
        [Parameter(Mandatory = $true)][scriptblock]$Instance
    )
    return [pscustomobject]@{ PSTypeName = "Horde.HostPort"; name = $Name; available = $true; reason = ""; handles = $Handles; instance = $Instance }
}

function New-HordeUnavailableHostPort {
    # A port for a host that cannot be asked - no adapter attached yet, or the adapter cannot reach
    # its terminal. Every answer through it is unknown with this reason, so a stored handle is never
    # verified against it (the lead's decision 2, 2026-09-30).
    param([Parameter(Mandatory = $true)][string]$Reason)
    if ("$Reason".Trim() -eq "") { throw "an unavailable host port needs a reason" }
    return [pscustomobject]@{ PSTypeName = "Horde.HostPort"; name = ""; available = $false; reason = $Reason; handles = $null; instance = $null }
}

function Assert-HordeHostPort {
    param($Port)
    if ($null -eq $Port -or @($Port.PSObject.TypeNames) -notcontains "Horde.HostPort") {
        throw "-HostPort must be made by New-HordeHostPort or New-HordeUnavailableHostPort"
    }
}

function ConvertTo-HordeHandleText {
    # A handle or window id as text: "12" for 12 and for "12". Anything that is not a whole number
    # or non-empty text is refused as $null, so a malformed id never becomes a key.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [int] -or $Value -is [long]) { if ($Value -lt 0) { return $null }; return ("" + $Value) }
    $t = "$Value"
    if ($t -cmatch '^[A-Za-z0-9._:-]{1,64}$') { return $t }
    return $null
}

function Read-HordeHostHandles {
    # The port's handle list as an answer: known @( { handle; window; tab; hostTitle } ), or unknown.
    # A list with a malformed or repeated handle is unknown as a whole: one bad row makes it
    # impossible to say which handles are live.
    param($Port)
    Assert-HordeHostPort $Port
    if (-not $Port.available) { return (New-HordeUnknown -Reason ("the host cannot be asked: " + $Port.reason)) }
    # Flattened one level, so a port may return its rows plainly or as one list with the unary comma
    # (PowerShell 5.1 delivers the second as a single element holding the list).
    $got = Invoke-HordeRead -What "the host's live handles" -Read { return , @(& $Port.handles | ForEach-Object { $_ }) }
    if ($got.state -ne "known") { return $got }
    $seen = @{}
    $rows = New-Object System.Collections.ArrayList
    foreach ($h in @($got.value)) {
        $hf = Get-HordeField -Record $h -Name "handle"
        $id = $null
        if ($hf.state -eq "known") { $id = ConvertTo-HordeHandleText $hf.value }
        if ($null -eq $id) { return (New-HordeUnknown -Reason "the host listed a handle that is not a well-formed id") }
        if ($seen.ContainsKey($id)) { return (New-HordeUnknown -Reason ("the host listed handle " + $id + " twice")) }
        $seen[$id] = $true
        $wf = Get-HordeField -Record $h -Name "window"
        $tf = Get-HordeField -Record $h -Name "tab"
        $tt = Get-HordeField -Record $h -Name "hostTitle"
        [void]$rows.Add([pscustomobject]@{
            handle = $id
            window = $(if ($wf.state -eq "known") { ConvertTo-HordeHandleText $wf.value } else { $null })
            tab = $(if ($tf.state -eq "known") { ConvertTo-HordeHandleText $tf.value } else { $null })
            hostTitle = $(if ($tt.state -eq "known") { "$($tt.value)" } else { $null })
        })
    }
    return (New-HordeKnown -Value $rows.ToArray())
}

function Read-HordeHostInstance {
    # The port's instance as an answer: known { id; startedAt; running; ambiguous }, or unknown.
    # startedAt must be a UTC-placeable [datetime] or $null; running a whole number.
    param($Port)
    Assert-HordeHostPort $Port
    if (-not $Port.available) { return (New-HordeUnknown -Reason ("the host cannot be asked: " + $Port.reason)) }
    $got = Invoke-HordeRead -What "the host instance" -Read { & $Port.instance }
    if ($got.state -ne "known") { return $got }
    $v = $got.value
    $run = Get-HordeField -Record $v -Name "running"
    if ($run.state -ne "known" -or ($run.value -isnot [int] -and $run.value -isnot [long]) -or $run.value -lt 0) {
        return (New-HordeUnknown -Reason "the host did not say how many instances are running")
    }
    $amb = Get-HordeField -Record $v -Name "ambiguous"
    $ambiguous = ($amb.state -eq "known" -and $amb.value -is [bool] -and $amb.value)
    $idf = Get-HordeField -Record $v -Name "id"
    $id = $null
    if ($idf.state -eq "known") { $id = ConvertTo-HordeHandleText $idf.value }
    $sf = Get-HordeField -Record $v -Name "startedAt"
    $started = $null
    if ($sf.state -eq "known") {
        if ($sf.value -isnot [datetime] -or $sf.value.Kind -eq [System.DateTimeKind]::Unspecified) {
            return (New-HordeUnknown -Reason "the host gave an instance start time that is not a placed [datetime]")
        }
        $started = $sf.value.ToUniversalTime()
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ id = $id; startedAt = $started; running = [int]$run.value; ambiguous = $ambiguous }))
}
