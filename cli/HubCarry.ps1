# cli/HubCarry - the hub carries the act requests `horde session` wrote down for a node that dials in,
# over the link that node dialled, and writes the node's answers back beside them.
#
# WHY (mesh v1, remote plan R19 over R17c). A node behind NAT cannot be dialled: the hub's own CLI can
# open no link to it, and `horde hub serve -Listen` meets it only in the round it dials into. So for a
# DIALLED node `horde session` writes its request down - <HordeHome>\hub\acts\<requestId>.json, the
# record cli/HubAct.ps1 already keeps for every act, marked via "dialled" - and waits; the hub, holding
# the node's link after its pull (cli/HubServe.ps1), sends every request waiting for that device, one
# after another, and writes each answer into its record. The record is the queue: one file per request,
# one place a request's state is read from, by the CLI and the hub alike. A record not marked dialled is
# the CLI's own (it opens its own link to a pulled node) and is never touched here.
#
# ONE LINK, ANY NUMBER OF SESSIONS (the founder's decision of 2026-10-11). Every request waiting for the
# device is carried on the one link, in the order it was issued; there is no per-link or per-node session
# limit here. What bounds spawns is the node's own policy - its daily cap (32 when it names none) and its
# permission ceiling (the top level when it names none) - checked on the node for every spawn, so a
# spawn above the cap comes back REFUSED by the node, with its reason, and is never sent again.
#
# WRITTEN DOWN BEFORE IT IS SENT, AND NEVER SENT BLIND AFTER (R19: "a request cut by a partition resolves
# through request.status"). The hub adds the send time to the record before the request leaves. A
# request whose answer never came - the link dropped, the node took longer than the hub waits - is then
# UNKNOWN: whether the node acted cannot be told, so the hub ends that link and, when the node next
# dials in, asks request.status about it before anything else:
#   - the node's journal has its outcome (done, failed, refused): that is the answer, written down;
#   - the journal holds it with no outcome yet (accepted): the node is still acting, or stopped while
#     acting; the record says so and the hub asks again next time;
#   - the journal does not hold it (absent): the node never received it, so it cannot have acted, and
#     the hub sends it again under the SAME id and issue time - which the journal would answer from its
#     record anyway (remote/Journal.ps1: an act happens once per request id);
#   - the journal cannot say: the record keeps the reason, and nothing is sent.
# A read (request.status asked for by `horde session status`) acts on nothing and is simply sent.
#
# ADMITTED BEFORE EVERY REQUEST (issue #124). Before each request the hub asks -Admit again, as the pull
# does before each of its own; a device revoked, expired or removed from the register mid-carry is told
# so in a bye and asked nothing more. The requests not yet sent are then settled REFUSED by the hub,
# never sent - the one answer the hub may give on its own, since it knows the node never saw them. A
# request already sent stays as it is: what the node did with it is the node's to say.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "HubAct.ps1")

# The route a dialled node's requests take: carried by the hub, never sent by the CLI.
$script:HordeHubDialledRoute = "dialled"
# The verbs carried that act. Anything else carried is a read, sent again freely.
$script:HordeHubCarryActVerbs = @("session.spawn", "session.close")
# How long the hub waits for a request.status answer about a request whose answer was lost: a read, so
# a minute, the link's silence window (remote/Clock.ps1).
$script:HordeHubCarryStatusMs = 60000

function Test-HordeHubActPending {
    # Is -Record still waiting for its answer? Neither an answer, a node's refusal, nor a read's result.
    param([Parameter(Mandatory = $true)]$Record)
    return ($null -eq (Get-HordeLinkProp $Record "answer") -and $null -eq (Get-HordeLinkProp $Record "error") -and $null -eq (Get-HordeLinkProp $Record "result"))
}

function Get-HordeHubCarryQueue {
    # The requests waiting for -DeviceId's dialled link, oldest first: { records; skipped }. A record
    # that cannot be read is skipped and said - never guessed at, never carried.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$DeviceId)
    $out = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return [pscustomobject]@{ records = @(); skipped = @() } }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter "*.json" -File | Where-Object { -not $_.Name.StartsWith(".") })) {
        $r = $null
        try { $r = [System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { [void]$skipped.Add("the hub's record " + $f.Name + " cannot be read, so it is not carried: " + $_.Exception.Message); continue }
        if ($null -eq $r) { [void]$skipped.Add("the hub's record " + $f.Name + " is empty, so it is not carried"); continue }
        if ("$(Get-HordeLinkProp $r 'via')" -cne $script:HordeHubDialledRoute -or "$($r.deviceId)" -cne $DeviceId) { continue }
        if (-not (Test-HordeHubActPending -Record $r)) { continue }
        # The record must be the one its file is named by: a request id is what the node journals.
        if ($f.Name -cne ("$($r.requestId)" + ".json")) { [void]$skipped.Add("the hub's record " + $f.Name + " names request " + $r.requestId + ", so it is not carried"); continue }
        [void]$out.Add($r)
    }
    $sorted = @($out | Sort-Object -Property @{ Expression = { "$($_.issuedAt)" } }, @{ Expression = { "$($_.requestId)" } })
    return [pscustomobject]@{ records = $sorted; skipped = $skipped.ToArray() }
}

function Set-HordeHubActProp {
    # Set -Name on -Record, adding it when a record written before it existed lacks it.
    param([Parameter(Mandatory = $true)]$Record, [Parameter(Mandatory = $true)][string]$Name, $Value)
    if ($null -ne $Record.PSObject.Properties[$Name]) { $Record.$Name = $Value } else { $Record | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Invoke-HordeHubCarryRequest {
    # One request on an open link: { answered; result; error; reason; seq }. answered is true when the
    # node's answer to it arrived (result, or error { code; reason }); false is "cannot say".
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)]$Contract, [int]$Seq, [Parameter(Mandatory = $true)][string]$Verb, $Arguments,
        [Parameter(Mandatory = $true)][string]$RequestId, [Parameter(Mandatory = $true)][string]$IssuedAt, [int]$TimeoutMs = 240000)
    $res = [pscustomobject]@{ answered = $false; result = $null; error = $null; reason = ""; seq = $Seq + 1 }
    $req = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = $res.seq; ts = (Get-HordeLinkTime); verb = $Verb; requestId = $RequestId; issuedAt = $IssuedAt; args = $Arguments }
    $why = Send-HordeHubFrame -Link $Link -Frame $req -Contract $Contract
    if ($why -ne "") { $res.reason = $why; return $res }
    $got = Receive-HordeHubFrame -Link $Link -Contract $Contract -TimeoutMs $TimeoutMs
    if ($null -eq $got.frame) { $res.reason = $got.reason; return $res }
    $r = $got.frame
    if ("$($r.kind)" -cne "res" -or "$($r.re)" -cne "$($req.id)") { $res.reason = "the node answered with a " + $r.kind + " frame that is not this request's answer"; return $res }
    $res.answered = $true
    $err = Get-HordeLinkProp $r "error"
    if ($null -ne $err) { $res.error = [pscustomobject]@{ code = "" + $err.code; reason = "" + $err.reason } } else { $res.result = $r.result }
    return $res
}

function Close-HordeHubCarryUnsent {
    # Settle every record in -Records that was never sent: refused by the hub, with -Reason. Returns the
    # lines said. A record already sent is left as it is (see the header).
    param([Parameter(Mandatory = $true)][string]$Dir, [object[]]$Records = @(), [Parameter(Mandatory = $true)][string]$Reason)
    $lines = New-Object System.Collections.ArrayList
    foreach ($rec in @($Records | Where-Object { $null -ne $_ })) {
        if (@(Get-HordeLinkProp $rec "sentAt" | Where-Object { "$_" -ne "" }).Count -gt 0) { continue }
        Set-HordeHubActProp -Record $rec -Name "error" -Value ([pscustomobject][ordered]@{ code = "refused"; reason = ("by the hub, never sent: " + $Reason) })
        Write-HordeHubActRecord -Dir $Dir -Record $rec
        [void]$lines.Add("REFUSED " + $rec.verb + " request " + $rec.requestId + " (by the hub, never sent): " + $Reason)
    }
    return $lines.ToArray()
}

function Invoke-HordeHubCarry {
    # Carry every request waiting for -DeviceId over -Link, a link that device dialled, bound and greeted
    # (cli/HubServe.ps1 has said hello and pulled). -Seq is the last seq the hub sent on it. Returns
    # { seq; lines }. It stops early, sending nothing more on the link, when an answer was lost (a late
    # one could be read as the next request's) or the device is no longer admitted (told in a bye).
    param([Parameter(Mandatory = $true)]$Link, [Parameter(Mandatory = $true)][string]$DeviceId, [Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)]$Contract,
        [int]$Seq = 0, [scriptblock]$Admit = $null, [int]$TimeoutMs = 240000, [int]$StatusTimeoutMs = $script:HordeHubCarryStatusMs)
    $seqNow = $Seq
    $lines = New-Object System.Collections.ArrayList
    $q = Get-HordeHubCarryQueue -Dir $Dir -DeviceId $DeviceId
    foreach ($l in @($q.skipped)) { [void]$lines.Add($l) }
    $queue = @($q.records)
    for ($i = 0; $i -lt $queue.Count; $i++) {
        $rec = $queue[$i]
        $rid = "$($rec.requestId)"
        $verb = "$($rec.verb)"
        $isAct = $script:HordeHubCarryActVerbs -ccontains $verb
        $sent = @(Get-HordeLinkProp $rec "sentAt" | Where-Object { "$_" -ne "" })
        # A record the hub could never send - a verb it does not carry, arguments the link contract
        # refuses (a record edited by hand) - is refused by the hub, never left to block the ones behind it.
        $bad = ""
        if ($script:HordeHubActVerbs -cnotcontains $verb) { $bad = "the hub does not carry " + $verb }
        else { $bad = Test-HordeHubActArgs -Contract $Contract -Verb $verb -Arguments $rec.args; if ($bad -ne "") { $bad = "the link contract refuses the request: " + $bad } }
        if ($bad -ne "") {
            Set-HordeHubActProp -Record $rec -Name "error" -Value ([pscustomobject][ordered]@{ code = "refused"; reason = ("by the hub, never sent: " + $bad) })
            Write-HordeHubActRecord -Dir $Dir -Record $rec
            [void]$lines.Add("REFUSED " + $verb + " request " + $rid + " (by the hub, never sent): " + $bad)
            continue
        }
        if ($isAct -and $sent.Count -gt 0) {
            # Sent before, its answer lost: ask what became of it, never send it blind (see the header).
            $cutAsk = Stop-HordeHubUnadmitted -Link $Link -DeviceId $DeviceId -Admit $Admit -Seq ($seqNow + 1) -Contract $Contract
            if ($cutAsk -ne "") { foreach ($l in @(Close-HordeHubCarryUnsent -Dir $Dir -Records @($queue[$i..($queue.Count - 1)]) -Reason $cutAsk)) { [void]$lines.Add($l) }; break }
            $st = Invoke-HordeHubCarryRequest -Link $Link -Contract $Contract -Seq $seqNow -Verb "request.status" -Arguments ([pscustomobject]@{ requestId = $rid }) -RequestId (New-HordeLinkFrameId) -IssuedAt (Get-HordeLinkTime) -TimeoutMs $StatusTimeoutMs
            $seqNow = $st.seq
            $sv = $st.result
            $said = ""
            if (-not $st.answered) { $said = "request.status got no answer: " + $st.reason }
            elseif ($null -ne $st.error) { $said = "request.status was refused: " + $st.error.code + ": " + $st.error.reason }
            elseif ("$($sv.state)" -ceq "known" -and @("done", "failed", "refused") -ccontains "$($sv.value.state)") {
                Set-HordeHubActProp -Record $rec -Name "answer" -Value $sv.value
                Set-HordeHubActProp -Record $rec -Name "note" -Value "settled from the node's journal by request.status, after its answer was lost"
                Write-HordeHubActRecord -Dir $Dir -Record $rec
                [void]$lines.Add((Format-HordeHubActAnswer -Res ([pscustomobject]@{ answered = $true; result = $sv; error = $null }) -RequestId $rid) + " (from the node's journal; its answer had been lost)")
                continue
            }
            elseif ("$($sv.state)" -ceq "known") {
                Set-HordeHubActProp -Record $rec -Name "note" -Value ("the node recorded it at " + $sv.value.receivedAt + " and has no outcome for it yet; the hub asks again when the node next dials in")
                Write-HordeHubActRecord -Dir $Dir -Record $rec
                [void]$lines.Add("WAITING " + $verb + " request " + $rid + ": the node holds it with no outcome yet")
                continue
            }
            elseif ("$($sv.state)" -cne "absent") { $said = "" + $sv.reason }
            if ($said -ne "") {
                Set-HordeHubActProp -Record $rec -Name "note" -Value ("whether the node acted is unknown: " + $said)
                Write-HordeHubActRecord -Dir $Dir -Record $rec
                [void]$lines.Add("UNKNOWN " + $verb + " request " + $rid + ": " + $said)
                # No answer to the status itself: nothing more goes on this link either.
                if (-not $st.answered) { break }
                continue
            }
            # Absent: the node never received it, so it never acted; sent again below under the same id.
            [void]$lines.Add("the node never recorded " + $verb + " request " + $rid + ", so the hub sends it again under the same id")
        }
        $cutSend = Stop-HordeHubUnadmitted -Link $Link -DeviceId $DeviceId -Admit $Admit -Seq ($seqNow + 1) -Contract $Contract
        if ($cutSend -ne "") { foreach ($l in @(Close-HordeHubCarryUnsent -Dir $Dir -Records @($queue[$i..($queue.Count - 1)]) -Reason $cutSend)) { [void]$lines.Add($l) }; break }
        # Written down as sent BEFORE it is sent: a hub that stops in between asks request.status next time.
        Set-HordeHubActProp -Record $rec -Name "sentAt" -Value @(@($sent) + @(Get-HordeLinkTime))
        Write-HordeHubActRecord -Dir $Dir -Record $rec
        $r = Invoke-HordeHubCarryRequest -Link $Link -Contract $Contract -Seq $seqNow -Verb $verb -Arguments $rec.args -RequestId $rid -IssuedAt "$($rec.issuedAt)" -TimeoutMs $TimeoutMs
        $seqNow = $r.seq
        if (-not $r.answered) {
            $said = $r.reason + "; whether the node acted is unknown, so the hub asks request.status when the node next dials in, and never sends it blind"
            if (-not $isAct) { $said = $r.reason + "; the hub sends it again when the node next dials in" }
            Set-HordeHubActProp -Record $rec -Name "note" -Value $said
            Write-HordeHubActRecord -Dir $Dir -Record $rec
            [void]$lines.Add("UNKNOWN " + $verb + " request " + $rid + ": " + $said)
            break  # an answer was lost: a late one could be read as the next request's, so nothing more goes on this link
        }
        if ($null -ne $r.error) { Set-HordeHubActProp -Record $rec -Name "error" -Value $r.error }
        elseif ("$($r.result.state)" -ceq "known" -and $isAct) { Set-HordeHubActProp -Record $rec -Name "answer" -Value $r.result.value }
        elseif ($isAct) {
            # The node answered, but its journal cannot say: kept waiting, asked about next time.
            Set-HordeHubActProp -Record $rec -Name "note" -Value ("the node could not say what happened: " + $r.result.reason)
        } else {
            Set-HordeHubActProp -Record $rec -Name "result" -Value $r.result
            if ("$($r.result.state)" -ceq "known") { Set-HordeHubActProp -Record $rec -Name "answer" -Value $r.result.value }
        }
        Write-HordeHubActRecord -Dir $Dir -Record $rec
        [void]$lines.Add((Format-HordeHubActAnswer -Res ([pscustomobject]@{ answered = $true; result = $r.result; error = $r.error }) -RequestId $rid))
    }
    return [pscustomobject]@{ seq = $seqNow; lines = $lines.ToArray() }
}

function Format-HordeHubCarriedRecord {
    # One line a person reads about a dialled node's request, from its record: the node's answer as
    # cli/HubAct.ps1 prints one, or, while it waits, whether it was ever sent and what the hub knows.
    param([Parameter(Mandatory = $true)]$Record)
    $rid = "$($Record.requestId)"
    $err = Get-HordeLinkProp $Record "error"
    if ($null -ne $err) { return (Format-HordeHubActAnswer -Res ([pscustomobject]@{ answered = $true; result = $null; error = $err }) -RequestId $rid) }
    $result = Get-HordeLinkProp $Record "result"
    if ($null -ne $result) { return (Format-HordeHubActAnswer -Res ([pscustomobject]@{ answered = $true; result = $result; error = $null }) -RequestId $rid) }
    $answer = Get-HordeLinkProp $Record "answer"
    if ($null -ne $answer) { return (Format-HordeHubActAnswer -Res ([pscustomobject]@{ answered = $true; result = ([pscustomobject]@{ state = "known"; value = $answer }); error = $null }) -RequestId $rid) }
    $note = "$(Get-HordeLinkProp $Record 'note')"
    $who = "node " + $Record.deviceId
    if (@(Get-HordeLinkProp $Record "sentAt" | Where-Object { "$_" -ne "" }).Count -eq 0) {
        return ("QUEUED " + $Record.verb + " request " + $rid + " for " + $who + ": not carried yet; horde hub serve -Listen carries it when the node next dials in")
    }
    if ($note -eq "") { $note = "sent, and no answer is recorded yet" }
    return ("UNKNOWN " + $Record.verb + " request " + $rid + " for " + $who + ": " + $note)
}

function Wait-HordeHubCarried {
    # Wait up to -TimeoutMs for the hub to carry -RequestId and record the node's answer, reading its
    # record every -PollMs. Returns the record as last read ($null when there is none). A read that
    # fails - the hub renaming its new copy into place at that moment - is read again next poll.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$RequestId, [int]$TimeoutMs = 240000, [int]$PollMs = 250)
    $until = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)
    $last = $null
    while ($true) {
        try { $r = Read-HordeHubActRecord -Dir $Dir -RequestId $RequestId; if ($null -ne $r) { $last = $r } } catch { }
        if ($null -ne $last -and -not (Test-HordeHubActPending -Record $last)) { return $last }
        if ([datetime]::UtcNow -ge $until) { return $last }
        Start-Sleep -Milliseconds $PollMs
    }
}
