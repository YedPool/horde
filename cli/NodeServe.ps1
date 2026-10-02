# cli/NodeServe - `horde node serve`: listen on the node's transport and answer each link.
#
# WHY HERE (remote plan step R12a). The serve loop holds a listener and a link, and reaches the session
# projection (core/Projection.ps1) and the device id (core/Device.ps1). remote/ may do none of that
# (tools/ExecScan.ps1), so the loop lives in cli/, and every answer it sends is built by
# remote/NodeServe.ps1, which is pure and tested frame by frame.
#
# WHAT IT DOES. Starts the listener once, then accepts links one after another. On each link it reads a
# frame, asks remote/NodeServe.ps1 what to answer, builds the session view only when a verb needs it
# (fresh for each such request: a list from the last request would be stale), sends the answer, and
# ends the link when the other side says bye, the frame was not one, or the link drops. It never acts:
# the verbs it answers are reads (R12a), and an act verb is refused as unsupported.
#
# WHAT IT DOES NOT. Install itself to start at logon (that is an install step, `horde install`), stream
# observe.since (R12b, after lifecycle step 11), or read a binding record (R12b, after Phase 3 step 3.8).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function New-HordeNodeManifest {
    # node.info's value (schema/node-manifest.v1): who this node is and what it offers. Hosts and
    # harnesses are the adapter folders present, by name, read from the tree and never written here.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Node, [Parameter(Mandatory = $true)][string]$Space)
    $version = "$(Get-Content -LiteralPath (Join-Path $Root 'VERSION') -TotalCount 1)".Trim()
    $osVersion = [System.Environment]::OSVersion.Version.ToString()
    $hosts = @(Get-ChildItem -LiteralPath (Join-Path $Root "hosts") -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch '^[a-z][a-z0-9-]{0,31}$' } | Sort-Object)
    $harnesses = @(Get-ChildItem -LiteralPath (Join-Path $Root "agents") -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch '^[a-z][a-z0-9-]{0,31}$' } | Sort-Object)
    return [ordered]@{
        schemaVersion = 1
        deviceId = "$($Node.deviceId)"
        deviceName = "$($Node.deviceName)"
        hordeVersion = $version
        os = [ordered]@{ family = "windows"; version = $osVersion }
        spaces = @($Space)
        hosts = $hosts
        harnesses = $harnesses
        # Profiles, repositories and admission come with engines E6 and lifecycle step 17; until then
        # the node offers none and says its admission state is unknown.
        profiles = @()
        repos = @()
        admission = [ordered]@{ tier = "default"; state = "unknown" }
        protocols = @(1)
        verbsVersions = @(1)
    }
}

function Send-HordeNodeAnswer {
    # Send one answer through the link's own writer. A result the writer refuses is replaced by an
    # internal error to the same request - one record the link cannot carry must not end the link - and
    # anything else it refuses ends the link. Returns $true while the link may go on.
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Frame)
    $bytes = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $State.contract
    if (-not $bytes.ok -and "$($Frame.kind)" -ceq "res") {
        $req = [pscustomobject]@{ verb = "$($Frame.verb)"; requestId = "$($Frame.requestId)"; id = "$($Frame.re)" }
        $bytes = ConvertTo-HordeFrameBytes -Frame (New-HordeNodeError -State $State -Request $req -Code "internal" -Reason ("the node's answer could not be sent: " + $bytes.reason)) -Contract $State.contract
    }
    if (-not $bytes.ok) {
        $bye = New-HordeLinkBye -Code "refused" -Reason ("the node could not send its answer: " + $bytes.reason) -Seq (Get-HordeNodeNextSeq $State) -Contract $State.contract
        $null = Send-HordeLinkFrame -Link $Link -Frame (ConvertTo-HordeWireText $bye)
        return $false
    }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes.bytes, 0, $bytes.bytes.Length - 1)
    $sent = Send-HordeLinkFrame -Link $Link -Frame $text
    return ("$($sent.state)" -ceq "known")
}

function Invoke-HordeNodeServe {
    # Serve links until -MaxLinks have been served (0: until stopped). -Transport is a loaded transport
    # (transports/Port.ps1: Resolve-HordeLinkTransport for the real one, Get-HordeTransport memory in a
    # test). -GetView is a script block that returns the session-view document (core/Projection.ps1's,
    # or a test's fake). Returns how many links were served, how each ended, and how many times the
    # listener was restarted.
    #
    # A FAULT IN ONE REQUEST IS AN ANSWER, NOT A CRASH. horde.ps1 runs with $ErrorActionPreference Stop,
    # and nothing restarts the node at logon yet (R12a), so a throw from the projection or from building
    # an answer is caught and answered as an internal error to that request; the link and the node go
    # on (review of this PR: a view with no observedAt killed the daemon).
    #
    # A BROKEN LISTENER IS RESTARTED, NEVER SPUN ON. An accept that fails at once, rather than after its
    # timeout, means the listener has nothing waiting (transports/local: no waiting instance); the loop
    # waits a second and listens again, and gives up after -RelistenLimit restarts in a row.
    #
    # LIMITS, written down: links are served one at a time, so a hub that keeps one link open holds the
    # node until it goes silent past -IdleTimeoutMs; each sessions.list or session.get builds the view
    # afresh; a node stopped with Ctrl+C sends no bye. All of it is inside the local transport's trust
    # boundary - this user, at this integrity level, on this machine.
    param(
        [Parameter(Mandatory = $true)]$Transport,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$Namespace,
        [Parameter(Mandatory = $true)][scriptblock]$GetView,
        [string]$JournalRoot = "",
        [int]$MaxLinks = 0,
        [int]$AcceptTimeoutMs = 15000,
        [int]$IdleTimeoutMs = 120000,
        [int]$RelistenLimit = 5,
        [scriptblock]$OnListening = $null
    )
    $listen = Start-HordeTransportListener -Transport $Transport -Endpoint $Endpoint
    if ($listen.state -cne "known") { throw ("the node could not listen on " + $Transport.name + " " + $Endpoint + ": " + $listen.reason) }
    $listener = $listen.value
    # Read once for every link this node serves; see New-HordeNodeServeState for what reading it costs.
    $contract = Get-HordeLinkContract
    $served = New-Object System.Collections.ArrayList
    $relistens = 0
    $inARow = 0
    try {
        if ($null -ne $OnListening) { & $OnListening }
        while ($MaxLinks -le 0 -or $served.Count -lt $MaxLinks) {
            $began = [datetime]::UtcNow
            $acc = Receive-HordeTransportLink -Listener $listener -TimeoutMs $AcceptTimeoutMs
            if ($acc.state -cne "known") {
                $took = ([datetime]::UtcNow - $began).TotalMilliseconds
                if ($took -ge ($AcceptTimeoutMs / 2)) { $inARow = 0; continue }
                $inARow++
                if ($inARow -gt $RelistenLimit) { throw ("the node's listener failed " + $inARow + " times in a row: " + $acc.reason) }
                Start-Sleep -Milliseconds 1000
                Stop-HordeTransportListener -Listener $listener
                $listen = Start-HordeTransportListener -Transport $Transport -Endpoint $Endpoint
                if ($listen.state -cne "known") { throw ("the node could not listen again on " + $Transport.name + " " + $Endpoint + ": " + $listen.reason) }
                $listener = $listen.value
                $relistens++
                continue
            }
            $inARow = 0
            $link = $acc.value
            $state = New-HordeNodeServeState -NodeId "$($Manifest.deviceId)" -NodeName "$($Manifest.deviceName)" -HordeVersion "$($Manifest.hordeVersion)" -Contract $contract
            $ended = "the link dropped"
            try {
                while ($true) {
                    $line = Receive-HordeLinkFrame -Link $link -TimeoutMs $IdleTimeoutMs
                    if ($line.state -cne "known") { $ended = "the link ended: " + $line.reason; break }
                    $data = [pscustomobject]@{ manifest = $Manifest; view = $null; viewError = ""; journalRoot = $JournalRoot; namespace = $Namespace }
                    $r = $null
                    try {
                        $r = Invoke-HordeNodeFrame -State $state -Line "$($line.value)" -Data $data
                        if ($r.needView) {
                            # Built afresh for each request that needs it: a list kept from an earlier
                            # request would be stale.
                            try { $data.view = & $GetView } catch { $data.viewError = "$($_.Exception.Message)" }
                            if ($null -eq $data.view -and $data.viewError -eq "") { $data.viewError = "the projection gave nothing" }
                            $r = Invoke-HordeNodeFrame -State $state -Line "$($line.value)" -Data $data
                        }
                    } catch {
                        $why = "$($_.Exception.Message)"
                        $req = $null
                        $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::GetEncoding(28591).GetBytes("$($line.value)")) -Contract $state.contract
                        if ($d.ok -and "$($d.frame.kind)" -ceq "req") { $req = $d.frame }
                        if ($null -ne $req) { $r = New-HordeNodeReply -Reply (New-HordeNodeError -State $state -Request $req -Code "internal" -Reason ("the node failed while answering: " + $why)) }
                        else { $r = New-HordeNodeReply -Reply (New-HordeLinkBye -Code "refused" -Reason ("the node failed while reading a frame: " + $why) -Seq (Get-HordeNodeNextSeq $state) -Contract $state.contract) -Close $true }
                    }
                    if ($null -ne $r.reply) {
                        if (-not (Send-HordeNodeAnswer -Link $link -State $state -Frame $r.reply)) { $ended = "the answer could not be sent"; break }
                    }
                    if ($r.close) { $ended = "closed by the protocol"; break }
                }
            } finally {
                Close-HordeLink -Link $link
            }
            [void]$served.Add($ended)
        }
    } finally {
        Stop-HordeTransportListener -Listener $listener
    }
    return [pscustomobject]@{ served = $served.Count; endings = $served.ToArray(); relistens = $relistens }
}
