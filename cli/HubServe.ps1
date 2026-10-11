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

# The preamble and hello-binding rules of a dialled link (see DIALLED LINKS below).
. (Join-Path (Split-Path -Parent $PSScriptRoot) "remote\LinkBinding.ps1")

# The one transport a node is served on before enrolment (cli/commands/node.ps1 serves on it).
$script:HordeHubOwnTransport = "local"
# How many copies of an unusable mirror are kept aside per node, newest first (review of PR #88).
$script:HordeHubAsideKept = 3
# HRESULT 0x80070020, ERROR_SHARING_VIOLATION: another process holds the hub's run lock.
$script:HordeHubSharingViolation = -2147024864
# HRESULT 0x80070021, ERROR_LOCK_VIOLATION: another process has locked a range of the file. With the
# sharing violation, the only failures read as a mirror "held open" (re-review of PR #88, F1).
$script:HordeHubLockViolation = -2147024863
# Each node's part of a round is bounded (issue #87, F10). 45 s: a node's sessions.list builds its
# projection, 11.4 s measured 2026-10-02, and node serve is opted out of power throttling, so 45 s
# is about four of those; nodes are pulled one after another, so a slow one costs the rest of the
# round at most this much.
$script:HordeHubNodeBudgetMs = 45000
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
    catch {
        # HELD OPEN IS NOT BAD (review of PR #88): a file another process holds without sharing read
        # cannot be opened, but its content may be a good mirror. Such an answer is marked held, so the
        # round leaves the file as it is rather than moving it aside and writing over its name.
        # HELD IS A SHARING OR LOCK VIOLATION ONLY (re-review of PR #88, F1): access denied, or any other
        # failure to open the file, is marked refused and said as its own cause; it was said as "held
        # open by another process", round after round, for a mirror its ACL denied.
        $inner = $_.Exception; while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        $u = New-HordeUnknown -Reason ("the mirror file " + $Path + " could not be read") -ErrorRecord $_
        $isHeld = ($inner -is [System.IO.IOException] -and ($inner.HResult -eq $script:HordeHubSharingViolation -or $inner.HResult -eq $script:HordeHubLockViolation))
        $isRefused = ((-not $isHeld) -and ($inner -is [System.UnauthorizedAccessException] -or ($inner -is [System.IO.IOException] -and $inner -isnot [System.IO.FileNotFoundException] -and $inner -isnot [System.IO.DirectoryNotFoundException])))
        $u | Add-Member -NotePropertyName held -NotePropertyValue $isHeld
        $u | Add-Member -NotePropertyName refused -NotePropertyValue $isRefused
        $u | Add-Member -NotePropertyName cause -NotePropertyValue $inner.Message
        return $u
    }
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

function Move-HordeHubMirrorAside {
    # Rename an unusable mirror to <name>.bad-<UTC stamp> beside it, and say where. The newest
    # $script:HordeHubAsideKept copies are kept and older ones removed, said so: a mirror unreadable
    # round after round left one more copy each round, without end (review of PR #88: 5 rounds, 5 copies).
    param([Parameter(Mandatory = $true)][string]$Path)
    $aside = $Path + ".bad-" + [datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmssfff'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    try { [System.IO.File]::Move($Path, $aside) }
    catch { return ("it could not be kept aside, and is overwritten: " + $_.Exception.Message) }
    $said = "kept aside as " + (Split-Path -Leaf $aside)
    # The stamp sorts as time does: one fixed-width format.
    $copies = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Path) -File -Filter ((Split-Path -Leaf $Path) + ".bad-*") | Sort-Object Name -Descending)
    $old = @($copies | Select-Object -Skip $script:HordeHubAsideKept)
    if ($old.Count -gt 0) {
        foreach ($c in $old) { Remove-Item -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue }
        $said = $said + "; " + $old.Count + " older cop" + $(if ($old.Count -eq 1) { "y" } else { "ies" }) + " removed, the newest " + $script:HordeHubAsideKept + " kept"
    }
    return $said
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

function New-HordeHubBound {
    # The bound on one node's part of a round (issue #87, F10): { deadline; seconds }, or no deadline
    # when -BudgetMs is 0.
    param([int]$BudgetMs = 0)
    if ($BudgetMs -le 0) { return [pscustomobject]@{ deadline = [datetime]::MaxValue; seconds = 0 } }
    return [pscustomobject]@{ deadline = [datetime]::UtcNow.AddMilliseconds($BudgetMs); seconds = [math]::Round($BudgetMs / 1000, 1) }
}

function Get-HordeHubWaitMs {
    # How long the next step may wait: -TimeoutMs, cut to what is left of -Bound. 0 when nothing is left.
    param([Parameter(Mandatory = $true)]$Bound, [int]$TimeoutMs)
    if ($Bound.deadline -eq [datetime]::MaxValue) { return $TimeoutMs }
    $left = [int][math]::Floor(($Bound.deadline - [datetime]::UtcNow).TotalMilliseconds)
    if ($left -le 0) { return 0 }
    return [math]::Min($TimeoutMs, $left)
}

# A step that fails within this much of the bound's deadline failed because of the bound. A wait cut
# to the bound ends on the receive's own reading of the clock, and [datetime]::UtcNow moves in steps
# (0.5 to 6 ms measured here, 2026-10-07), so it could end a few ms short of the deadline and be said as
# a plain timeout: "no frame within 2767 ms" on a 3 s bound (remote run c2-dial, 2026-10-07).
$script:HordeHubBoundSlackMs = 50

function Get-HordeHubPastBound {
    # The reason a step failed, said as the bound when the bound is what ran out (within
    # $script:HordeHubBoundSlackMs of its deadline).
    param([Parameter(Mandatory = $true)]$Bound, [string]$Reason)
    if ($Bound.deadline -ne [datetime]::MaxValue -and [datetime]::UtcNow -ge $Bound.deadline.AddMilliseconds(-$script:HordeHubBoundSlackMs)) { return ("the node's part of the round ran past its " + $Bound.seconds + " s bound: " + $Reason) }
    return $Reason
}

function Receive-HordeHubFrame {
    # The next frame from the node, as the link's decoder accepts it: { frame; reason }. -Bound cuts the
    # wait to what is left of the node's bound.
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs, $Bound = (New-HordeHubBound))
    $wait = Get-HordeHubWaitMs -Bound $Bound -TimeoutMs $TimeoutMs
    if ($wait -le 0) { return [pscustomobject]@{ frame = $null; reason = (Get-HordeHubPastBound -Bound $Bound -Reason "no time was left to wait for the node") } }
    $got = Receive-HordeLinkFrame -Link $Link -TimeoutMs $wait
    if ("$($got.state)" -cne "known") { return [pscustomobject]@{ frame = $null; reason = (Get-HordeHubPastBound -Bound $Bound -Reason ("no frame from the node: " + $got.reason)) } }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::GetEncoding(28591).GetBytes("$($got.value)")) -Contract $Contract
    if (-not $d.ok) { return [pscustomobject]@{ frame = $null; reason = ("the node sent a frame the hub refuses: " + $d.reason) } }
    if ("$($d.frame.kind)" -ceq "bye") { return [pscustomobject]@{ frame = $null; reason = ("the node ended the link: " + $d.frame.bye.code + ": " + $d.frame.bye.reason) } }
    return [pscustomobject]@{ frame = $d.frame; reason = "" }
}

# DIALLED LINKS (remote plan R17c). A node behind NAT dials the hub's listener over ssh; the forced
# command, R17a's clittach.ps1, dials the hub pipe for it and first writes one preamble line naming
# the device its key is enrolled as, taken from its own argv, never from the node. The hub binds the
# link to that device and refuses a hello claiming another.
#
# ONE COPY OF THE CONTRACT (issue #144, item 7): the preamble and the hello rule are
# remote/LinkBinding.ps1's (Read-HordeAttachPreamble, Test-HordeHelloBinding), called here, never
# restated. This file kept two stand-ins until R17a landed; a stand-in is a second copy that drifts.

function Invoke-HordeHubPull {
    # One pull from one node: { ok; reason; nodeName; list; nodeSentAt; receivedAt; clock }. -Entry is a
    # registry entry with its transport resolved: { deviceId; deviceName; endpoint; transport;
    # transportError }. -Hub is { id; name; hordeVersion }. Every failure is a reason, never a throw of
    # its own; a throw from below is the caller's to catch (Update-HordeHubNode does).
    # -BudgetMs bounds the whole pull, the open and every wait in it (issue #87, F10: a node that took
    # every timeout held the round for about 195 s, 15 s to open and 60 s for each of three answers).
    # -Link is a link the node dialled (R17c), already bound to -Entry's device: nothing is opened, and
    # the exchange is the same.
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs = 60000, [int]$BudgetMs = 0, $Link = $null)
    $res = [pscustomobject]@{ ok = $false; reason = ""; nodeName = ""; list = $null; nodeSentAt = $null; receivedAt = $null; clock = $null }
    $bound = New-HordeHubBound -BudgetMs $BudgetMs
    if ($null -ne $Link) { $link = $Link }
    else {
        if ($null -eq $Entry.transport) { $res.reason = "the hub has no transport for this node: " + $Entry.transportError; return $res }
        $open = Open-HordeTransportLink -Transport $Entry.transport -Endpoint "$($Entry.endpoint)" -Role "hub" -TimeoutMs ([Math]::Max(1, (Get-HordeHubWaitMs -Bound $bound -TimeoutMs ([Math]::Min($TimeoutMs, 15000)))))
        if ("$($open.state)" -cne "known") { $res.reason = Get-HordeHubPastBound -Bound $bound -Reason ("could not open a link: " + $open.reason); return $res }
        $link = $open.value
    }
    $seq = 0
    try {
        $t = Get-HordeLinkTime
        $seq++
        $hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = $seq; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "$($Hub.id)"; name = "$($Hub.name)"; protocols = @($script:HordeLinkProtocols); verbsVersions = @($script:HordeHubVerbsVersions); hordeVersion = "$($Hub.hordeVersion)"; t1 = $t } }
        $why = Send-HordeHubFrame -Link $link -Frame $hello -Contract $Contract
        if ($why -ne "") { $res.reason = $why; return $res }
        $got = Receive-HordeHubFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs -Bound $bound
        if ($null -eq $got.frame) { $res.reason = $got.reason; return $res }
        $f = $got.frame
        $refusal = ""
        if ("$($f.kind)" -cne "hello") { $refusal = "the node answered the hello with a " + $f.kind + " frame" }
        elseif ("$($f.hello.role)" -cne "node") { $refusal = "the other end says its role is '" + $f.hello.role + "', not node" }
        else { $refusal = (@(Test-HordeHelloBinding -Frame $f -BoundDeviceId "$($Entry.deviceId)") -join "; ") }
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
        $got = Receive-HordeHubFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs -Bound $bound
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
        $got = Receive-HordeHubFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs -Bound $bound
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
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs = 60000, [int]$BudgetMs = 0, $Link = $null)
    $who = "node " + $Entry.deviceName + " (" + $Entry.deviceId + ")"
    $note = ""
    try {
        $mirrorPath = Get-HordeHubMirrorPath -Root $Root -DeviceId "$($Entry.deviceId)"
        $old = Read-HordeHubMirror -Path $mirrorPath -DeviceId "$($Entry.deviceId)" -Contract $Contract
        $m = $null
        # A mirror another process holds open is left as it is: this node's round is skipped, said so.
        if ($old.state -ceq "unknown" -and $null -ne $old.PSObject.Properties["held"] -and $old.held -eq $true) {
            return ($who + ": its mirror is held open by another process (" + $old.reason + "); left as it is, nothing pulled or written this round")
        }
        # A mirror that cannot be opened for any other reason is left as it is too, and the cause is said.
        if ($old.state -ceq "unknown" -and $null -ne $old.PSObject.Properties["refused"] -and $old.refused -eq $true) {
            return ($who + ": its mirror could not be opened: " + $old.cause + "; left as it is, nothing pulled or written this round")
        }
        if ($old.state -ceq "known") { $m = $old.value }
        else {
            $m = New-HordeNodeMirror -DeviceId "$($Entry.deviceId)" -DeviceName "$($Entry.deviceName)"
            # Never overwritten unseen (issue #87, F8): an unreadable mirror is renamed aside first, so its
            # last-known inventory survives for a person to look at, and a missing one is said.
            if ($old.state -ceq "unknown") { $note = "; the old mirror was started afresh: " + $old.reason + "; " + (Move-HordeHubMirrorAside -Path $mirrorPath) }
            else { $note = "; no mirror file was there; started afresh" }
        }
        $p = $null
        # A failure is dated from when this pull began: an unreachable node can take the transport's
        # whole open timeout to say so (15 s on the local link), and "since" is when the hub tried.
        $began = [datetime]::UtcNow
        try { $p = Invoke-HordeHubPull -Entry $Entry -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $BudgetMs -Link $Link }
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

function Get-HordeHubListenEndpoint {
    # Where the hub listens for dialled links on its own transport: "hub:<hubId>", the endpoint R17a's
    # attach dials and the local transport makes the hub pipe of.
    param([Parameter(Mandatory = $true)][string]$HubId)
    return ("hub:" + $HubId)
}

function Invoke-HordeHubDialled {
    # One link a node dialled: read its preamble, bind it to that device, and run that node's part of
    # the round over it (Update-HordeHubNode). Returns the line saying what happened. The link is always
    # closed here, whatever happened: a node's part can return before it pulls (a mirror held open).
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs = 60000, [int]$BudgetMs = 0)
    try {
        $first = Receive-HordeLinkFrame -Link $Link -TimeoutMs ([Math]::Min($TimeoutMs, 15000))
        if ($first.state -cne "known") { return ("a dialled link was refused: no preamble came: " + $first.reason) }
        $dev = Read-HordeAttachPreamble -Line "$($first.value)"
        if ($dev.state -cne "known") { return ("a dialled link was refused: " + $dev.reason) }
        $entry = [pscustomobject]@{ deviceId = "$($dev.value)"; deviceName = "(dialled)"; endpoint = "(dialled)"; transport = $null; transportError = "" }
        return (Update-HordeHubNode -Entry $entry -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $BudgetMs -Link $Link)
    } finally { Close-HordeLink -Link $Link }
}

function Receive-HordeHubDialled {
    # Accept links on -Listener until -WindowMs has passed, running each one's part as it comes.
    # Returns the lines. A failed accept that is not the window running out is said, and the window
    # goes on: one broken peer does not end the hub's listening.
    param([Parameter(Mandatory = $true)]$Listener, [Parameter(Mandatory = $true)][int]$WindowMs, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs = 60000, [int]$BudgetMs = 0)
    $lines = New-Object System.Collections.ArrayList
    $until = [datetime]::UtcNow.AddMilliseconds($WindowMs)
    while ($true) {
        $left = [int]($until - [datetime]::UtcNow).TotalMilliseconds
        if ($left -le 0) { break }
        $acc = Receive-HordeTransportLink -Listener $Listener -TimeoutMs $left
        if ($acc.state -ceq "known") { [void]$lines.Add((Invoke-HordeHubDialled -Link $acc.value -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $BudgetMs)); continue }
        if ([datetime]::UtcNow -lt $until) {
            [void]$lines.Add("a dialled link could not be accepted: " + $acc.reason)
            # An accept that fails at once would spin; a short pause bounds it.
            Start-Sleep -Milliseconds 250
        }
    }
    return $lines.ToArray()
}

function Get-HordeHubLockPath {
    # The hub's run lock: serve.lock in the folder that holds the mirror folder.
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path (Split-Path -Parent $Root) "serve.lock")
}

function Enter-HordeHubLock {
    # Take the hub's run lock, or throw (issue #87, F9: two hubs each marked the node unreachable while
    # the other held its one link, and raced on each mirror). The pattern of `horde metrics collect`
    # (core/MetricsCollect.ps1): a file held with no sharing is released by the system when its holder
    # dies, so a killed hub never leaves it locked; only a sharing violation means another hub, and any
    # other failure to open it is said as itself, never as "busy" (review of PR #70, F8).
    param([Parameter(Mandatory = $true)][string]$Path)
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    try { return [System.IO.File]::Open($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
    catch {
        $inner = $_.Exception; while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.IO.IOException] -and $inner.HResult -eq $script:HordeHubSharingViolation) { throw ("another horde hub serve is running: it holds " + $Path) }
        throw ("the hub's run lock could not be opened, so the hub did not start: " + $inner.Message)
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
        # The bound on each node's part of a round; 0 for none. See $script:HordeHubNodeBudgetMs.
        [int]$NodeBudgetMs = $script:HordeHubNodeBudgetMs,
        [scriptblock]$OnRound = $null,
        # A listener nodes dial (R17c): between rounds the hub accepts links on it instead of sleeping,
        # and each dialled node's part is in the round it came in. With a listener the last round
        # waits its interval too, so a node can still dial into it.
        $Listener = $null
    )
    $lock = Enter-HordeHubLock -Path (Get-HordeHubLockPath -Root $Root)
    try {
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
        foreach ($e in @($Nodes | Where-Object { $null -ne $_ })) { [void]$outcomes.Add((Update-HordeHubNode -Entry $e -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $NodeBudgetMs)) }
        if ($done.Count -eq 0) { foreach ($l in $swept) { [void]$outcomes.Add($l) } }
        if ($null -ne $Listener) {
            $window = $IntervalMs - [int]([datetime]::UtcNow - $began).TotalMilliseconds
            foreach ($l in @(Receive-HordeHubDialled -Listener $Listener -WindowMs ([Math]::Max(0, $window)) -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $NodeBudgetMs)) { [void]$outcomes.Add($l) }
        }
        $round = [pscustomobject]@{ at = (Get-HordeLinkTime -At $began); outcomes = $outcomes.ToArray() }
        [void]$done.Add($round)
        # Whatever the block writes is not a round: discarded, so the return is only the rounds.
        if ($null -ne $OnRound) { $null = & $OnRound $round }
        if ($Rounds -gt 0 -and $done.Count -ge $Rounds) { break }
        $left = $IntervalMs - [int]([datetime]::UtcNow - $began).TotalMilliseconds
        if ($left -gt 0) { Start-Sleep -Milliseconds $left }
    }
    return $done.ToArray()
    } finally { $lock.Dispose() }
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
