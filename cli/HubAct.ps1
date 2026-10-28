# cli/HubAct - the hub's side of an act: ask one node to start or close a session, and keep what it
# answered.
#
# THE ACT PATH'S A4 (planning/execution-plan-remote.md, R19's first version, 2026-10-05). A request is
# one link to the node: hello, the act request, its answer, bye. The node records the request before it
# acts and answers with its journal entry (remote/NodeServe.ps1, cli/NodeAct.ps1), so a request cut
# off by a dropped link is sent again with the SAME request id and issue time and is answered from the
# journal - the node acts once. That is why the hub writes each request down before it sends it:
# <HordeHome>\hub\acts\<requestId>.json holds the verb, the node, the arguments and the issue time,
# and then the answer. A close takes the process to expect from the spawn's answer kept there.
#
# THE HANDSHAKE is cli/HubServe.ps1's (Invoke-HordeHubPull), repeated here rather than moved: that file
# is under review in another pull request (#88), and the duplication goes when both have merged.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
# ConvertFrom-HordeJson reads the hub's records (T-0366): under 7 bare ConvertFrom-Json turned issuedAt into a
# [datetime], and the req carried from it failed the link's time pattern.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")

$script:HordeHubActProtocols = @(1)
$script:HordeHubActVerbsVersions = @(1)
$script:HordeHubActVerbs = @("session.spawn", "session.close", "request.status")

function Get-HordeHubActDir {
    param([Parameter(Mandatory = $true)][string]$HomeRoot)
    return (Join-Path $HomeRoot "hub\acts")
}

function Write-HordeHubActRecord {
    # One request's record, written whole: a temporary file, then one rename over the old one.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)]$Record)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $final = Join-Path $Dir ("" + $Record.requestId + ".json")
    $tmp = Join-Path $Dir ("." + $Record.requestId + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllText($tmp, ($Record | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $final -Force
}

function New-HordeHubActRecord {
    # A request as the hub writes it down before it is sent: a new request id, issued now. -Via
    # "dialled" marks one the hub carries over the link the node dials in (cli/HubCarry.ps1); "" is one
    # the CLI sends itself over a link it opens.
    param([Parameter(Mandatory = $true)][string]$Verb, [Parameter(Mandatory = $true)][string]$DeviceId, $Arguments, [string]$Via = "")
    $rec = [pscustomobject][ordered]@{ requestId = (New-HordeLinkFrameId); verb = $Verb; deviceId = $DeviceId; issuedAt = (Get-HordeLinkTime); args = $Arguments; answer = $null; error = $null; sentAt = @() }
    if ($Via -ne "") { $rec | Add-Member -NotePropertyName via -NotePropertyValue $Via }
    return $rec
}

function New-HordeHubCloseArgs {
    # session.close's arguments for the session a spawn record started: the process its node named when
    # it started it, with that process's namespace (R11), so the node refuses if its view differs.
    param([Parameter(Mandatory = $true)]$Spawn, [string]$Reason = "closed by the hub")
    $ex = $Spawn.answer.expect
    return [pscustomobject][ordered]@{ sessionId = "" + $Spawn.answer.sessionId; expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $ex.ns.device; space = "" + $ex.ns.space }; pid = [long]$ex.pid; procStart = "" + $ex.procStart }; reason = $Reason }
}

function Read-HordeHubActRecord {
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$RequestId)
    $p = Join-Path $Dir ($RequestId + ".json")
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    return (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($p)))
}

function Find-HordeHubSpawn {
    # The spawn whose answer names -SessionId and carries the process to expect, as an answer: known
    # record, absent, or unknown when two records claim it or a record cannot be read. A spawn answered
    # done or FAILED with its process is closable - #104 answers a session that runs at a level it was not
    # asked for and could not be ended, or runs without its work, as failed with its process, to be closed
    # again (review of #126, F1). A refused spawn, or one with no process, started nothing to close.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$SessionId)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return (New-HordeAbsent -Note "the hub has started no session") }
    $hits = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter "*.json" -File)) {
        $r = $null
        # A record that cannot be read could be a second claim: the answer is unknown, never one picked.
        try { $r = ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($f.FullName)) } catch { return (New-HordeUnknown -Reason ("the hub's record " + $f.Name + " cannot be read, so whether it claims the session " + $SessionId + " cannot be told: " + $_.Exception.Message)) }
        if ("" + $r.verb -cne "session.spawn" -or $null -eq $r.answer) { continue }
        $ex = Get-HordeLinkProp $r.answer "expect"
        $closable = (@("done", "failed") -ccontains ("" + $r.answer.state)) -and $null -ne $ex -and "" + $ex.pid -ne ""
        if ($closable -and "" + $r.answer.sessionId -ceq $SessionId) { [void]$hits.Add($r) }
    }
    if ($hits.Count -eq 0) { return (New-HordeAbsent -Note ("the hub has no record of starting the session " + $SessionId)) }
    if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $hits.Count + " of the hub's records claim the session " + $SessionId)) }
    return (New-HordeKnown -Value $hits[0])
}

function Resolve-HordeHubCloseTarget {
    # The node a close goes to, as an answer: the node the spawn record names. -Node, when given, must
    # name that same node, by id or by name in -Entries; another node is refused here, naming both
    # (review of #126).
    param([Parameter(Mandatory = $true)]$Spawn, [string]$Node = "", $Entries = @())
    $own = "" + $Spawn.deviceId
    if ($Node -eq "") { return (New-HordeKnown -Value $own) }
    $m = @(@($Entries) | Where-Object { "" + $_.deviceId -ceq $Node -or "" + $_.deviceName -ceq $Node })
    $named = $Node
    if ($m.Count -eq 1) { $named = "" + $m[0].deviceId }
    if ($named -cne $own) { return (New-HordeUnknown -Reason ("the session was started on node " + $own + ", and -Node names " + $Node + $(if ($named -cne $Node) { " (" + $named + ")" } else { "" }) + "; a close goes only to the node that started it")) }
    return (New-HordeKnown -Value $own)
}

function Resolve-HordeHubActTarget {
    # The node -Target names, by device id or name, as an answer: known { deviceId; deviceName; route },
    # route "pulled" for a node in -Pulled (the registry the hub opens links to: its own node) and
    # "dialled" for one in -Enrolled (the hub's register: cli/HubRegistry.ps1's Get-HordeHubListedNodes,
    # each with the deviceName its mirror last heard, or ""), whose requests the hub carries over the link
    # it dials in (cli/HubCarry.ps1). Unknown, with the reason, when nothing or more than one device
    # answers to -Target, or when the one that does is enrolled but not live (revoked, expired, an entry
    # that cannot be trusted): such a request is refused before anything is written.
    param([string]$Target, $Pulled = @(), $Enrolled = @())
    $known = New-Object System.Collections.ArrayList
    foreach ($e in @($Pulled | Where-Object { $null -ne $_ })) { [void]$known.Add([pscustomobject]@{ deviceId = "" + $e.deviceId; deviceName = "" + $e.deviceName; route = "pulled"; live = $true; reason = "" }) }
    foreach ($e in @($Enrolled | Where-Object { $null -ne $_ })) { [void]$known.Add([pscustomobject]@{ deviceId = "" + $e.deviceId; deviceName = "" + $e.deviceName; route = "dialled"; live = [bool]$e.live; reason = "" + $e.reason }) }
    $hits = @($known | Where-Object { $_.deviceId -ceq $Target -or ($_.deviceName -ne "" -and $_.deviceName -ceq $Target) })
    if ($hits.Count -eq 0) {
        $names = @($known | ForEach-Object { $(if ($_.deviceName -ne "") { $_.deviceName } else { "(unnamed)" }) + " (" + $_.deviceId + $(if ($_.route -ceq "dialled") { ", dialled" } else { "" }) + ")" })
        return (New-HordeUnknown -Reason ("the hub has no registered or enrolled node '" + $Target + "'; it knows " + $(if ($names.Count -gt 0) { $names -join ", " } else { "none" })))
    }
    if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("'" + $Target + "' names " + $hits.Count + " nodes (" + (@($hits | ForEach-Object { $_.deviceId }) -join ", ") + "); name it by its device id")) }
    $h = $hits[0]
    if (-not $h.live) { return (New-HordeUnknown -Reason ("node " + $h.deviceId + " is not enrolled live, so nothing is sent to it: " + $h.reason)) }
    return (New-HordeKnown -Value ([pscustomobject][ordered]@{ deviceId = $h.deviceId; deviceName = $h.deviceName; route = $h.route }))
}

function Test-HordeHubActArgs {
    # "" when a request with these arguments passes the link contract, else the contract's reason. Checked
    # before anything is written or sent, so a request the contract refuses is REFUSED here, never sent and
    # never left for a resend that cannot succeed (review of #126).
    param([Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$Verb, $Arguments)
    $probe = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = $Verb; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = $Arguments }
    $b = ConvertTo-HordeFrameBytes -Frame $probe -Contract $Contract
    if ($b.ok) { return "" }
    return ("" + $b.reason)
}

function Send-HordeHubActFrame {
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$Frame, [Parameter(Mandatory = $true)]$Contract)
    $b = ConvertTo-HordeFrameBytes -Frame $Frame -Contract $Contract
    if (-not $b.ok) { return ("the hub could not send its " + $Frame.kind + ": " + $b.reason) }
    $sent = Send-HordeLinkFrame -Link $Link -Frame ([System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1))
    if ("$($sent.state)" -cne "known") { return ("the hub could not send its " + $Frame.kind + ": " + $sent.reason) }
    return ""
}

function Receive-HordeHubActFrame {
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$Contract, [int]$TimeoutMs)
    $got = Receive-HordeLinkFrame -Link $Link -TimeoutMs $TimeoutMs
    if ("$($got.state)" -cne "known") { return [pscustomobject]@{ frame = $null; reason = ("no frame from the node: " + $got.reason) } }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::GetEncoding(28591).GetBytes("$($got.value)")) -Contract $Contract
    if (-not $d.ok) { return [pscustomobject]@{ frame = $null; reason = ("the node sent a frame the hub refuses: " + $d.reason) } }
    if ("$($d.frame.kind)" -ceq "bye") { return [pscustomobject]@{ frame = $null; reason = ("the node ended the link: " + $d.frame.bye.code + ": " + $d.frame.bye.reason) } }
    return [pscustomobject]@{ frame = $d.frame; reason = "" }
}

function Invoke-HordeHubAct {
    # One act request to one node over one link: { answered; result; error; reason }. answered is true
    # when the node's answer to this request arrived: result is then its answer (a tristate record whose
    # known value is the journal entry), or error its refusal { code; reason }. answered false is "the
    # hub cannot say what happened": send the same request again, or ask request.status.
    # -Entry: { deviceId; endpoint; transport; transportError }. -Hub: { id; name; hordeVersion }.
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)]$Hub, [Parameter(Mandatory = $true)]$Contract,
        [Parameter(Mandatory = $true)][string]$Verb, [Parameter(Mandatory = $true)]$Arguments,
        [Parameter(Mandatory = $true)][string]$RequestId, [Parameter(Mandatory = $true)][string]$IssuedAt, [int]$TimeoutMs = 240000)
    $res = [pscustomobject]@{ answered = $false; result = $null; error = $null; reason = ""; refusedHere = $false }
    if ($script:HordeHubActVerbs -cnotcontains $Verb) { $res.reason = "the hub does not send " + $Verb; return $res }
    $bad = Test-HordeHubActArgs -Contract $Contract -Verb $Verb -Arguments $Arguments
    if ($bad -ne "") { $res.refusedHere = $true; $res.reason = "the link contract refuses the request, so nothing was sent: " + $bad; return $res }
    if ($null -eq $Entry.transport) { $res.reason = "the hub has no transport for this node: " + $Entry.transportError; return $res }
    $open = Open-HordeTransportLink -Transport $Entry.transport -Endpoint "$($Entry.endpoint)" -Role "hub" -TimeoutMs 15000
    if ("$($open.state)" -cne "known") { $res.reason = "could not open a link: " + $open.reason; return $res }
    $link = $open.value
    $seq = 0
    try {
        $t = Get-HordeLinkTime
        $seq++
        $hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = $seq; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "$($Hub.id)"; name = "$($Hub.name)"; protocols = @($script:HordeHubActProtocols); verbsVersions = @($script:HordeHubActVerbsVersions); hordeVersion = "$($Hub.hordeVersion)"; t1 = $t } }
        $why = Send-HordeHubActFrame -Link $link -Frame $hello -Contract $Contract
        if ($why -ne "") { $res.reason = $why; return $res }
        $got = Receive-HordeHubActFrame -Link $link -Contract $Contract -TimeoutMs 60000
        if ($null -eq $got.frame) { $res.reason = $got.reason; return $res }
        $f = $got.frame
        $refusal = ""
        if ("$($f.kind)" -cne "hello") { $refusal = "the node answered the hello with a " + $f.kind + " frame" }
        elseif ("$($f.hello.role)" -cne "node") { $refusal = "the other end says its role is '" + $f.hello.role + "', not node" }
        elseif ("$($f.hello.id)" -cne "$($Entry.deviceId)") { $refusal = "the node at endpoint " + $Entry.endpoint + " answered as device " + $f.hello.id + ", not " + $Entry.deviceId }
        if ($refusal -ne "") {
            $seq++
            $null = Send-HordeHubActFrame -Link $link -Frame (New-HordeLinkBye -Code "refused" -Reason $refusal -Seq $seq -Contract $Contract) -Contract $Contract
            $res.reason = $refusal
            return $res
        }
        $chosen = Resolve-HordeLinkHello -Hello $f -Seq ($seq + 1) -Contract $Contract
        if ($null -ne $chosen.bye) { $null = Send-HordeHubActFrame -Link $link -Frame $chosen.bye -Contract $Contract; $res.reason = "" + $chosen.bye.bye.reason; return $res }
        $seq++
        $req = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = $seq; ts = (Get-HordeLinkTime); verb = $Verb; requestId = $RequestId; issuedAt = $IssuedAt; args = $Arguments }
        $why = Send-HordeHubActFrame -Link $link -Frame $req -Contract $Contract
        if ($why -ne "") { $res.reason = $why; return $res }
        # A spawn waits for the node to start the session and read its mode back (cli/NodeAct.ps1's
        # bounds, about two minutes at most), so this wait is longer than a read's.
        $got = Receive-HordeHubActFrame -Link $link -Contract $Contract -TimeoutMs $TimeoutMs
        if ($null -eq $got.frame) { $res.reason = $got.reason + "; whether the node acted is unknown: send the same request again, or ask request.status"; return $res }
        $r = $got.frame
        if ("$($r.kind)" -cne "res" -or "$($r.re)" -cne "$($req.id)") { $res.reason = "the node answered with a frame that is not this request's answer"; return $res }
        $res.answered = $true
        $err = Get-HordeLinkProp $r "error"
        if ($null -ne $err) { $res.error = [pscustomobject]@{ code = "" + $err.code; reason = "" + $err.reason } }
        else { $res.result = $r.result }
        $seq++
        $null = Send-HordeHubActFrame -Link $link -Frame (New-HordeLinkBye -Code "shutdown" -Reason "the hub's request is answered" -Seq $seq -Contract $Contract) -Contract $Contract
        return $res
    } finally {
        Close-HordeLink -Link $link
    }
}

function Format-HordeHubActAnswer {
    # One line a person reads: what the node did with the request.
    param([Parameter(Mandatory = $true)]$Res, [Parameter(Mandatory = $true)][string]$RequestId)
    if ($null -ne $Res.PSObject.Properties["refusedHere"] -and $Res.refusedHere) { return ("REFUSED request " + $RequestId + " (by the hub, nothing sent): " + $Res.reason) }
    if (-not $Res.answered) { return ("UNKNOWN request " + $RequestId + ": " + $Res.reason) }
    if ($null -ne $Res.error) { return ("REFUSED request " + $RequestId + " (" + $Res.error.code + "): " + $Res.error.reason) }
    if ("" + $Res.result.state -cne "known") { return ("UNKNOWN request " + $RequestId + ": " + $Res.result.reason) }
    $v = $Res.result.value
    # The entry names its own request: for request.status that is the request asked about, not this one.
    $rid = $RequestId
    if ("" + $v.requestId -ne "") { $rid = "" + $v.requestId }
    $line = ($("" + $v.state).ToUpperInvariant() + " " + $v.verb + " request " + $rid)
    if ("" + $v.sessionId -ne "") { $line += " session " + $v.sessionId }
    $ex = Get-HordeLinkProp $v "expect"
    if ($null -ne $ex) { $line += " pid " + $ex.pid + " procStart " + $ex.procStart }
    if ("" + $v.reason -ne "") { $line += ": " + $v.reason }
    return $line
}
