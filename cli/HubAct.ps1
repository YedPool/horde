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

function Read-HordeHubActRecord {
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$RequestId)
    $p = Join-Path $Dir ($RequestId + ".json")
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json)
}

function Find-HordeHubSpawn {
    # The done spawn whose answer names -SessionId, as an answer: known record, absent, or unknown when
    # two records claim it.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$SessionId)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return (New-HordeAbsent -Note "the hub has started no session") }
    $hits = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter "*.json" -File)) {
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { continue }
        if ("" + $r.verb -cne "session.spawn" -or $null -eq $r.answer) { continue }
        if ("" + $r.answer.state -ceq "done" -and "" + $r.answer.sessionId -ceq $SessionId) { [void]$hits.Add($r) }
    }
    if ($hits.Count -eq 0) { return (New-HordeAbsent -Note ("the hub has no record of starting the session " + $SessionId)) }
    if ($hits.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $hits.Count + " of the hub's records claim the session " + $SessionId)) }
    return (New-HordeKnown -Value $hits[0])
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
    $res = [pscustomobject]@{ answered = $false; result = $null; error = $null; reason = "" }
    if ($script:HordeHubActVerbs -cnotcontains $Verb) { $res.reason = "the hub does not send " + $Verb; return $res }
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
    if (-not $Res.answered) { return ("UNKNOWN request " + $RequestId + ": " + $Res.reason) }
    if ($null -ne $Res.error) { return ("REFUSED request " + $RequestId + " (" + $Res.error.code + "): " + $Res.error.reason) }
    if ("" + $Res.result.state -cne "known") { return ("UNKNOWN request " + $RequestId + ": " + $Res.result.reason) }
    $v = $Res.result.value
    $line = ($("" + $v.state).ToUpperInvariant() + " " + $v.verb + " request " + $RequestId)
    if ("" + $v.sessionId -ne "") { $line += " session " + $v.sessionId }
    $ex = Get-HordeLinkProp $v "expect"
    if ($null -ne $ex) { $line += " pid " + $ex.pid + " procStart " + $ex.procStart }
    if ("" + $v.reason -ne "") { $line += ": " + $v.reason }
    return $line
}
