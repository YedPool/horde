# cli/HubServe - `horde hub serve` and `horde nodes`: pull each node's inventory, keep its mirror file.
#
# WHY HERE (remote plan step R13a). Pulling holds a link, and the mirror is a file on disk; remote/ may
# do neither beyond its journal (tools/ExecScan.ps1), so the loop and the files live in cli/, as the
# node's own loop does (cli/NodeServe.ps1). What the hub may SAY from a mirror is remote/Mirror.ps1's,
# pure and tested without a link.
#
# WHAT A ROUND DOES. For each registered node: open a link over the node's transport, say hello as the
# hub, refuse a node that answers as another device, ping once for a clock sample (R6), ask
# sessions.list, say bye. The list replaces the mirror's last one (Update-HordeNodeMirror); any failure
# is a reason recorded in the mirror (Set-HordeNodeMirrorLost), so the node's sessions turn unknown,
# never absent. Then the mirror is written, through a temporary file that becomes it.
#
# WHY A LINK PER ROUND, NOT ONE HELD OPEN. `horde node serve` serves one link at a time (its LIMITS,
# cli/NodeServe.ps1), so a hub holding a link would hold the node from every other client, and each
# sessions.list builds the node's projection afresh anyway (11.4 s, measured 2026-10-02). A round every
# 20 s keeps a heard node inside the link's 60 s silence window (remote/Clock.ps1) with two rounds to
# spare.
#
# THE REGISTRY is the hub's own node, dialled at its device id over the local link: the hub is always
# also a node (remote design, decision 1), and another node is added only by enrolment (R17). A node that
# dials in to the hub, through the listener and shim of R17, arrives with R17 too.
#
# A MIRROR FILE IS TRUSTED ONLY AFTER IT IS CHECKED, on write and on read: schema/node-mirror.v1 for its
# own fields, and the link contract itself for the inventory it holds - the list and the carried
# sessions are encoded by the link's own writer (ConvertTo-HordeFrameBytes) as the sessions.list result
# they were, so the file and the wire cannot drift apart. A file that fails either is unknown with the
# reason, never a guessed mirror.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# The one transport a node is served on before enrolment (cli/commands/node.ps1 serves on it).
$script:HordeHubOwnTransport = "local"
# The verbs versions this hub speaks (link-verbs v1).
$script:HordeHubVerbsVersions = @(1)
# Unicode without a byte-order mark: a mirror file is the hub's own and read back by this file only.
# Callers load core/ReadShared.ps1 and core/FileAtomic.ps1 (Read-HordeSharedText, Move-HordeFileAtomic).
$script:HordeHubMirrorEncoding = New-Object System.Text.UTF8Encoding($false)

function Get-HordeHubRegistry {
    # The nodes the hub pulls: its own, by its device id. -Node is core/Device.ps1's Get-HordeNode.
    param([Parameter(Mandatory = $true)]$Node)
    return @([pscustomobject]@{ deviceId = "$($Node.deviceId)"; deviceName = "$($Node.deviceName)"; endpoint = "$($Node.deviceId)"; transportName = $script:HordeHubOwnTransport })
}

function Get-HordeHubMirrorRoot {
    param([Parameter(Mandatory = $true)][string]$HomeRoot)
    return (Join-Path $HomeRoot "hub\mirror")
}

function Get-HordeHubMirrorPath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$DeviceId)
    if ($DeviceId -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z') { throw ("not a device id: '" + $DeviceId + "'") }
    return (Join-Path $Root ($DeviceId + ".json"))
}

function New-HordeHubListFrame {
    # A sessions.list result frame holding -List, for the link's own writer to check: the one check the
    # wire applies, applied to the file.
    param([Parameter(Mandatory = $true)]$List)
    $t = Get-HordeLinkTime
    return [pscustomobject][ordered]@{ v = 1; kind = "res"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; verb = "sessions.list"; requestId = (New-HordeLinkFrameId); re = (New-HordeLinkFrameId); result = [pscustomobject][ordered]@{ state = "known"; value = $List; reason = ""; observedAt = $t } }
}

function Test-HordeHubMirror {
    # Findings for a parsed mirror; empty when it may be trusted. See the file header.
    param([Parameter(Mandatory = $true)]$Mirror, [Parameter(Mandatory = $true)]$Contract)
    $found = @(Test-HordeSchema -Value $Mirror -Schema (Get-HordeSchema -Name "node-mirror.v1"))
    if ($found.Count -gt 0) { return @($found | ForEach-Object { "node-mirror.v1: " + $_ }) }
    $inv = Get-HordeLinkProp $Mirror "inventory"
    if ($null -eq $inv) { return @() }
    $out = New-Object System.Collections.ArrayList
    $b = ConvertTo-HordeFrameBytes -Frame (New-HordeHubListFrame -List $inv.list) -Contract $Contract
    if (-not $b.ok) { [void]$out.Add("the inventory is not a sessions.list the link contract accepts: " + $b.reason) }
    $carried = @($inv.carried | Where-Object { $null -ne $_ } | ForEach-Object { $_.session })
    if ($carried.Count -gt 0) {
        $at = Get-HordeLinkTime
        $asList = [pscustomobject][ordered]@{ complete = [pscustomobject][ordered]@{ state = "known"; value = $false; reason = "carried"; observedAt = $at }; sessions = $carried; observedAt = $at }
        $b = ConvertTo-HordeFrameBytes -Frame (New-HordeHubListFrame -List $asList) -Contract $Contract
        if (-not $b.ok) { [void]$out.Add("the carried sessions are not sessions the link contract accepts: " + $b.reason) }
    }
    return @($out)
}

function Read-HordeHubMirror {
    # A node's mirror file: known, the mirror; absent when there is no file; unknown with the reason when
    # it cannot be read, is not one to trust, or names another device than -DeviceId, the one its file
    # is named by (review of PR #86, F6: <A>.json holding B's mirror read as B's, and the next write then
    # went to B.json).
    #
    # READ WITH EVERY SHARE (core/ReadShared.ps1): ReadAllText's ordinary read share made the hub's
    # write fail whenever `horde nodes` read at the same moment (review of PR #86, F3).
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)]$Contract)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeAbsent -Note ("no mirror file at " + $Path)) }
    $m = $null
    try { $m = Read-HordeSharedText -Path $Path | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason ("the mirror file " + $Path + " could not be read") -ErrorRecord $_) }
    if ($null -eq $m) { return (New-HordeUnknown -Reason ("the mirror file " + $Path + " could not be read: it is empty")) }
    $found = @(Test-HordeHubMirror -Mirror $m -Contract $Contract)
    if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("the mirror file " + $Path + " could not be read as a mirror: " + ($found -join "; "))) }
    if ("$($m.deviceId)" -cne $DeviceId) { return (New-HordeUnknown -Reason ("the mirror file " + $Path + " holds the mirror of device " + $m.deviceId + ", not " + $DeviceId)) }
    return (New-HordeKnown -Value $m)
}

function Get-HordeHubMirrorTemps {
    # The temporary files a write of this device's mirror leaves only when it is killed between writing
    # and renaming: <deviceId>.json.<32 hex>.tmp, beside the mirror.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$DeviceId)
    $name = Split-Path -Leaf (Get-HordeHubMirrorPath -Root $Root -DeviceId $DeviceId)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -File -Filter ($name + ".*.tmp") | Where-Object { $_.Name -cmatch ('\A' + [regex]::Escape($name) + '\.[0-9a-f]{32}\.tmp\z') } | Sort-Object LastWriteTimeUtc -Descending)
}

function Clear-HordeHubMirrorTemps {
    # Recover, then clean up, what killed writes left (review of PR #86, F3: 5 of 60 kills left a temp
    # file, and nothing removed it). A temp is a whole, checked mirror - it was checked before it was
    # written - so when the mirror itself is missing or cannot be read, the newest temp that reads as
    # this device's mirror is renamed into its place. Every other temp is removed. Returns one line per
    # file acted on.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)]$Contract)
    $path = Get-HordeHubMirrorPath -Root $Root -DeviceId $DeviceId
    $out = New-Object System.Collections.ArrayList
    $have = (Read-HordeHubMirror -Path $path -DeviceId $DeviceId -Contract $Contract).state -ceq "known"
    foreach ($t in @(Get-HordeHubMirrorTemps -Root $Root -DeviceId $DeviceId)) {
        if (-not $have -and (Read-HordeHubMirror -Path $t.FullName -DeviceId $DeviceId -Contract $Contract).state -ceq "known") {
            Move-HordeFileAtomic -From $t.FullName -To $path
            $have = $true
            [void]$out.Add("recovered " + $t.Name + " as " + (Split-Path -Leaf $path))
            continue
        }
        Remove-Item -LiteralPath $t.FullName -Force
        [void]$out.Add("removed " + $t.Name)
    }
    return $out.ToArray()
}

function Write-HordeHubMirror {
    # Write a mirror, checked first, through a temporary file in the same folder that is then renamed
    # over the old one in one step (core/FileAtomic.ps1, the precedent of PR #70): a reader or a kill
    # sees the old mirror or the new one, never half of one and never neither. Returns the path.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Mirror, [Parameter(Mandatory = $true)]$Contract)
    $found = @(Test-HordeHubMirror -Mirror $Mirror -Contract $Contract)
    if ($found.Count -gt 0) { throw ("this mirror is not one to write: " + ($found -join "; ")) }
    $path = Get-HordeHubMirrorPath -Root $Root -DeviceId "$($Mirror.deviceId)"
    [void][System.IO.Directory]::CreateDirectory($Root)
    $tmp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    $bytes = $script:HordeHubMirrorEncoding.GetBytes(($Mirror | ConvertTo-Json -Depth 40 -Compress))
    $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
    try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    # A rename that fails while this process lives leaves no temp behind; only a kill does, and
    # Clear-HordeHubMirrorTemps recovers or removes those when the hub starts.
    try { Move-HordeFileAtomic -From $tmp -To $path }
    catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }
    return $path
}

function Send-HordeHubFrame {
    # One frame through the link's own writer. Returns "" when sent, or why not.
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$Frame, [Parameter(Mandatory = $true)]$Contract)
    $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $Contract
    if (-not $b.ok) { return ("the hub could not send its " + $Frame.kind + ": " + $b.reason) }
    $sent = Send-HordeLinkFrame -Link $Link -Frame ([System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1))
    if ("$($sent.state)" -cne "known") { return ("the hub could not send its " + $Frame.kind + ": " + $sent.reason) }
    return ""
}

function Receive-HordeHubFrame {
    # The next frame from the node, as the link's decoder accepts it: { frame; reason }.
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs)
    $got = Receive-HordeLinkFrame -Link $Link -TimeoutMs $TimeoutMs
    if ("$($got.state)" -cne "known") { return [pscustomobject]@{ frame = $null; reason = ("no frame from the node: " + $got.reason) } }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::GetEncoding(28591).GetBytes("$($got.value)")) -Contract $Contract
    if (-not $d.ok) { return [pscustomobject]@{ frame = $null; reason = ("the node sent a frame the hub refuses: " + $d.reason) } }
    if ("$($d.frame.kind)" -ceq "bye") { return [pscustomobject]@{ frame = $null; reason = ("the node ended the link: " + $d.frame.bye.code + ": " + $d.frame.bye.reason) } }
    return [pscustomobject]@{ frame = $d.frame; reason = "" }
}

function Invoke-HordeHubPull {
    # One pull from one node: { ok; reason; nodeName; list; nodeSentAt; receivedAt; clock }. -Entry is a
    # registry entry with its transport resolved: { deviceId; deviceName; endpoint; transport;
    # transportError }. -Hub is { id; name; hordeVersion }. Every failure is a reason, never a throw of
    # its own; a throw from below is the caller's to catch (Update-HordeHubNode does).
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs = 60000)
    $res = [pscustomobject]@{ ok = $false; reason = ""; nodeName = ""; list = $null; nodeSentAt = $null; receivedAt = $null; clock = $null }
    if ($null -eq $Entry.transport) { $res.reason = "the hub has no transport for this node: " + $Entry.transportError; return $res }
    $open = Open-HordeTransportLink -Transport $Entry.transport -Endpoint "$($Entry.endpoint)" -Role "hub" -TimeoutMs ([Math]::Min($TimeoutMs, 15000))
    if ("$($open.state)" -cne "known") { $res.reason = "could not open a link: " + $open.reason; return $res }
    $link = $open.value
    $seq = 0
    try {
        $t = Get-HordeLinkTime
        $seq++
        $hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = $seq; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "$($Hub.id)"; name = "$($Hub.name)"; protocols = @($script:HordeLinkProtocols); verbsVersions = @($script:HordeHubVerbsVersions); hordeVersion = "$($Hub.hordeVersion)"; t1 = $t } }
        $why = Send-HordeHubFrame -Link $link -Frame $hello -Contract $Contract
        if ($why -ne "") { $res.reason = $why; return $res }
        $got = Receive-HordeHubFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs
        if ($null -eq $got.frame) { $res.reason = $got.reason; return $res }
        $f = $got.frame
        $refusal = ""
        if ("$($f.kind)" -cne "hello") { $refusal = "the node answered the hello with a " + $f.kind + " frame" }
        elseif ("$($f.hello.role)" -cne "node") { $refusal = "the other end says its role is '" + $f.hello.role + "', not node" }
        elseif ("$($f.hello.id)" -cne "$($Entry.deviceId)") { $refusal = "the node at endpoint " + $Entry.endpoint + " answered as device " + $f.hello.id + ", not " + $Entry.deviceId }
        if ($refusal -ne "") {
            $seq++
            $null = Send-HordeHubFrame -Link $link -Frame (New-HordeLinkBye -Code "refused" -Reason $refusal -Seq $seq -Contract $Contract) -Contract $Contract
            $res.reason = $refusal
            return $res
        }
        $chosen = Resolve-HordeLinkHello -Hello $f -Seq ($seq + 1) -Contract $Contract
        if ($null -ne $chosen.bye) {
            $null = Send-HordeHubFrame -Link $link -Frame $chosen.bye -Contract $Contract
            $res.reason = "" + $chosen.bye.bye.reason
            return $res
        }
        $res.nodeName = "$($f.hello.name)"
        # One ping: the four timestamps of R6's clock sample. t1 is read back from the text sent, so the
        # sample measures what the node saw.
        $seq++
        $ping = [pscustomobject][ordered]@{ v = 1; kind = "ping"; id = (New-HordeLinkFrameId); seq = $seq; ts = (Get-HordeLinkTime); ping = [pscustomobject][ordered]@{ t1 = (Get-HordeLinkTime) } }
        $why = Send-HordeHubFrame -Link $link -Frame $ping -Contract $Contract
        if ($why -ne "") { $res.reason = $why; return $res }
        $got = Receive-HordeHubFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs
        $t4 = [datetime]::UtcNow
        if ($null -eq $got.frame) { $res.reason = $got.reason; return $res }
        $res.clock = New-HordeUnknown -Reason "the node's answer to the ping was not its pong"
        if ("$($got.frame.kind)" -ceq "pong" -and "$($got.frame.re)" -ceq "$($ping.id)") {
            $pong = $got.frame.pong
            $res.clock = Get-HordeClockSample -T1 (ConvertFrom-HordeMirrorTime "$($pong.t1)") -T2 (ConvertFrom-HordeMirrorTime "$($pong.t2)") -T3 (ConvertFrom-HordeMirrorTime "$($pong.t3)") -T4 $t4
        }
        $seq++
        $req = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = $seq; ts = (Get-HordeLinkTime); verb = "sessions.list"; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = [pscustomobject]@{} }
        $why = Send-HordeHubFrame -Link $link -Frame $req -Contract $Contract
        if ($why -ne "") { $res.reason = $why; return $res }
        $got = Receive-HordeHubFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs
        $received = [datetime]::UtcNow
        if ($null -eq $got.frame) { $res.reason = $got.reason; return $res }
        $r = $got.frame
        if ("$($r.kind)" -cne "res" -or "$($r.re)" -cne "$($req.id)") { $res.reason = "the node answered sessions.list with a " + $r.kind + " frame that is not its answer"; return $res }
        if ($null -ne (Get-HordeLinkProp $r "error")) { $res.reason = "the node answered sessions.list with an error: " + $r.error.code + ": " + $r.error.reason; return $res }
        if ("$($r.result.state)" -cne "known") { $res.reason = "the node could not list its sessions: " + $r.result.reason; return $res }
        $sentAt = ConvertFrom-HordeMirrorTime "$($r.ts)"
        if ($null -eq $sentAt) { $res.reason = "the node's answer carries no send time the hub can read"; return $res }
        $res.list = $r.result.value
        $res.nodeSentAt = $sentAt
        $res.receivedAt = $received
        $res.ok = $true
        $seq++
        $null = Send-HordeHubFrame -Link $link -Frame (New-HordeLinkBye -Code "shutdown" -Reason "the hub's round is done" -Seq $seq -Contract $Contract) -Contract $Contract
        return $res
    } finally {
        Close-HordeLink -Link $link
    }
}

function Update-HordeHubNode {
    # One node's part of a round: read its mirror, pull, record the result, write the mirror. Returns one
    # line saying what happened. A throw anywhere is that line, never the end of the hub (as the node's
    # own loop answers a fault rather than crash, cli/NodeServe.ps1).
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs = 60000)
    $who = "node " + $Entry.deviceName + " (" + $Entry.deviceId + ")"
    $note = ""
    try {
        $old = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $Root -DeviceId "$($Entry.deviceId)") -DeviceId "$($Entry.deviceId)" -Contract $Contract
        $m = $null
        if ($old.state -ceq "known") { $m = $old.value }
        else {
            $m = New-HordeNodeMirror -DeviceId "$($Entry.deviceId)" -DeviceName "$($Entry.deviceName)"
            if ($old.state -ceq "unknown") { $note = "; the old mirror was started afresh: " + $old.reason }
        }
        $p = $null
        # A failure is dated from when this pull began: an unreachable node can take the transport's
        # whole open timeout to say so (15 s on the local link), and "since" is when the hub tried.
        $began = [datetime]::UtcNow
        try { $p = Invoke-HordeHubPull -Entry $Entry -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs }
        catch { $p = [pscustomobject]@{ ok = $false; reason = ("the hub failed while pulling: " + $_.Exception.Message) } }
        $line = ""
        if ($p.ok) {
            $m = Update-HordeNodeMirror -Mirror $m -List $p.list -NodeSentAt $p.nodeSentAt -ReceivedAt $p.receivedAt -Clock $p.clock -DeviceName $p.nodeName
            $line = $who + ": heard, " + @($p.list.sessions).Count + " session(s)"
        } else {
            $m = Set-HordeNodeMirrorLost -Mirror $m -At $began -Reason "$($p.reason)"
            $line = $who + ": unreachable: " + $p.reason
        }
        $null = Write-HordeHubMirror -Root $Root -Mirror $m -Contract $Contract
        return ($line + $note)
    } catch {
        return ($who + ": the hub failed: " + $_.Exception.Message + $note)
    }
}

function Invoke-HordeHubServe {
    # Pull every node, once per round, until -Rounds rounds are done (0: until stopped). -Nodes are
    # registry entries with their transports resolved. Returns one { at; outcomes } per round.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Nodes,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Hub,
        [Parameter(Mandatory = $true)]$Contract,
        [int]$Rounds = 0,
        [int]$IntervalMs = 20000,
        [int]$TimeoutMs = 60000,
        [scriptblock]$OnRound = $null
    )
    $done = New-Object System.Collections.ArrayList
    # What a killed hub left: recovered or removed before the first round reads a mirror.
    $swept = New-Object System.Collections.ArrayList
    foreach ($e in @($Nodes | Where-Object { $null -ne $_ })) {
        try { foreach ($l in @(Clear-HordeHubMirrorTemps -Root $Root -DeviceId "$($e.deviceId)" -Contract $Contract)) { [void]$swept.Add("node " + $e.deviceName + " (" + $e.deviceId + "): " + $l) } }
        catch { [void]$swept.Add("node " + $e.deviceName + " (" + $e.deviceId + "): its temporary files could not be cleared: " + $_.Exception.Message) }
    }
    while ($Rounds -le 0 -or $done.Count -lt $Rounds) {
        $began = [datetime]::UtcNow
        $outcomes = New-Object System.Collections.ArrayList
        foreach ($e in @($Nodes | Where-Object { $null -ne $_ })) { [void]$outcomes.Add((Update-HordeHubNode -Entry $e -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs)) }
        if ($done.Count -eq 0) { foreach ($l in $swept) { [void]$outcomes.Add($l) } }
        $round = [pscustomobject]@{ at = (Get-HordeLinkTime -At $began); outcomes = $outcomes.ToArray() }
        [void]$done.Add($round)
        # Whatever the block writes is not a round: discarded, so the return is only the rounds.
        if ($null -ne $OnRound) { $null = & $OnRound $round }
        if ($Rounds -gt 0 -and $done.Count -ge $Rounds) { break }
        $left = $IntervalMs - [int]([datetime]::UtcNow - $began).TotalMilliseconds
        if ($left -gt 0) { Start-Sleep -Milliseconds $left }
    }
    return $done.ToArray()
}

function ConvertTo-HordeNodesRecord {
    param($Answer)
    return (ConvertTo-HordeAnswerRecord $Answer)
}

function ConvertTo-HordeNodesReport {
    # `horde nodes -Json`: the fleet view with every answer in its stored form (state, value, reason,
    # observedAt), so a reader never meets an answer without its state.
    param([Parameter(Mandatory = $true)]$Fleet)
    $nodes = @($Fleet.nodes | ForEach-Object {
        [ordered]@{ deviceId = $_.deviceId; deviceName = $_.deviceName; heard = (ConvertTo-HordeNodesRecord $_.heard); heardAt = $_.heardAt; complete = (ConvertTo-HordeNodesRecord $_.complete); listed = $_.listed; carried = $_.carried; clockFault = (ConvertTo-HordeNodesRecord $_.clockFault) }
    })
    $sessions = @($Fleet.sessions | ForEach-Object {
        $row = $_
        $fields = [ordered]@{}
        foreach ($k in @($row.fields.Keys)) { $fields[$k] = ConvertTo-HordeNodesRecord $row.fields[$k] }
        $out = [ordered]@{ device = $row.device; deviceName = $row.deviceName; sessionId = $row.sessionId; agent = $row.agent; presence = (ConvertTo-HordeNodesRecord $row.presence); fields = $fields; ns = $row.ns; lastSeenAt = $row.lastSeenAt; lastKnown = $row.lastKnown }
        if ($null -ne $row.PSObject.Properties["twoDevices"]) { $out["twoDevices"] = @($row.twoDevices) }
        $out
    })
    return [ordered]@{ observedAt = $Fleet.observedAt; nodes = $nodes; sessions = $sessions; faults = @($Fleet.faults) }
}

function Format-HordeNodesText {
    # `horde nodes` for a person: one line per node, then one per fault.
    param([Parameter(Mandatory = $true)]$Report)
    $lines = New-Object System.Collections.ArrayList
    foreach ($n in @($Report.nodes)) {
        $who = $n.deviceName + " (" + $n.deviceId + ")"
        # The node's own reason names it (remote/Mirror.ps1, Get-HordeMirrorNodeAnswer).
        if ($n.heard.state -cne "known") { [void]$lines.Add($n.heard.reason); continue }
        $inv = "inventory partial: " + $n.complete.reason
        if ($n.complete.state -ceq "known" -and $n.complete.value -eq $true) { $inv = "inventory complete" }
        $line = $who + ": heard at " + $n.heardAt + ", " + $n.listed + " session(s), " + $inv
        if ($n.carried -gt 0) { $line = $line + ", " + $n.carried + " carried from earlier inventories" }
        if ($n.clockFault.state -ceq "known" -and $n.clockFault.value -eq $true) { $line = $line + ", CLOCK FAULT: its clock is past the skew allowance" }
        [void]$lines.Add($line)
    }
    foreach ($f in @($Report.faults)) { [void]$lines.Add("fault: session " + $f.sessionId + " is listed on " + @($f.devices).Count + " devices (" + (@($f.devices) -join ", ") + ")") }
    if (@($Report.nodes).Count -eq 0) { [void]$lines.Add("no node is registered") }
    return $lines.ToArray()
}
