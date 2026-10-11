$HordeCommand = @{
    name    = "session"
    group   = "hub"
    usage   = "session spawn -Node <device> -Label <L> -Run <runId> -Profile <p> -Repo <repoId> -Prompt <text> [-Role orc] [-Title <t>] [-Permission <level>] [-Worktree <name> -Branch <b>] [-HostName <h>] | session close -SessionId <id> [-Node <device>] [-Reason <why>] | session status -RequestId <id> [-Node <device>] | any of them -Resend <requestId>"
    summary = "ask a node to start or close a session (remote plan R19): one request per id, written down before it is sent, so a request whose answer was lost is sent again with -Resend and acted on once; a node that dials in (enrolled with horde hub enroll) gets its requests carried by horde hub serve -Listen over the link it dials, and this command waits for the answer"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("spawn", "close", "status")][string]$Verb,
            # The node: its device id or name. A spawn must name it (review of #126): no default to the hub's
            # own machine. A close goes to the node the spawn record names; a status to the request's node.
            [string]$Node = "",
            [string]$Label = "", [string]$Role = "orc", [string]$Run = "", [string]$Profile = "", [string]$Repo = "",
            [string]$Prompt = "", [string]$Title = "", [string]$Permission = "", [string]$Worktree = "", [string]$Branch = "",
            [string]$HostName = "", [ValidateSet("proof", "routed")][string]$CloseOn = "proof",
            [string]$SessionId = "", [string]$Reason = "closed by the hub", [string]$RequestId = "",
            # Send a request the hub wrote down earlier again, with the same id and issue time.
            [string]$Resend = "",
            [int]$TimeoutSeconds = 240
        )
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        foreach ($t in @(Get-HordeTransportFiles)) { . $t }
        . (Join-Path $root "remote\Protocol.ps1")
        . (Join-Path $root "cli\HubServe.ps1")
        . (Join-Path $root "cli\HubAct.ps1")
        . (Join-Path $root "cli\HubRegistry.ps1")
        $me = Get-HordeNode
        $version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()
        $hub = [pscustomobject]@{ id = $me.deviceId; name = $me.deviceName; hordeVersion = $version }
        $hordeHome = Get-HordeHome
        $actDir = Get-HordeHubActDir -HomeRoot $hordeHome
        $contract = Get-HordeLinkContract
        # Every node a request may go to: what `horde nodes` lists (cli/HubRegistry.ps1's
        # Get-HordeHubListedNodes) - the registry the hub opens links to (its own node), and every node the
        # hub's register holds live, which dials in - each dialled one named as its mirror last heard it.
        $pulled = @(Get-HordeHubRegistry -Node $me)
        $mirrorRoot = Get-HordeHubMirrorRoot -HomeRoot $hordeHome
        $enrolled = @(Get-HordeHubListedNodes -Own @() -HordeHome $hordeHome | ForEach-Object {
            $name = ""
            try { $m = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $_.deviceId) -DeviceId $_.deviceId -Contract $contract; if ($m.state -ceq "known") { $name = "" + $m.value.deviceName } } catch { }
            if ($name -ceq "(dialled)") { $name = "" }
            [pscustomobject]@{ deviceId = "" + $_.deviceId; deviceName = $name; live = $true; reason = "" }
        })
        # A node the register holds but not live (revoked, expired) is named with why, so a request to it
        # is refused saying so rather than "no such node".
        if ($Node -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' -and @($enrolled | Where-Object { $_.deviceId -ceq $Node }).Count -eq 0) {
            $k = Get-HordeHubEnrolledKey -HordeHome $hordeHome -DeviceId $Node
            if ($k.state -ceq "unknown") { $enrolled += [pscustomobject]@{ deviceId = $Node; deviceName = ""; live = $false; reason = "" + $k.reason } }
        }

        # The request: written down first, or read back to be sent again.
        $rec = $null
        if ($Resend -ne "") {
            $rec = Read-HordeHubActRecord -Dir $actDir -RequestId $Resend
            if ($null -eq $rec) { throw ("the hub has no record of request " + $Resend) }
        } else {
            $args2 = $null
            $target = $Node
            switch ($Verb) {
                "spawn" {
                    if ($Node -eq "") { throw "session spawn needs -Node: the node is always named, never defaulted to the hub's own machine" }
                    if ($Label -eq "" -or $Run -eq "" -or $Profile -eq "" -or $Repo -eq "" -or $Prompt -eq "") { throw "session spawn needs -Label, -Run, -Profile, -Repo and -Prompt: the profile is one the node offers, named by the hub" }
                    $a = [ordered]@{ label = $Label; role = $Role; runId = $Run; profile = $Profile; repoId = $Repo; prompt = [pscustomobject]@{ text = $Prompt }; closeOn = $CloseOn }
                    if ($Title -ne "") { $a["title"] = $Title }
                    if ($Permission -ne "") { $a["permission"] = $Permission }
                    if ($HostName -ne "") { $a["host"] = $HostName }
                    if ($Worktree -ne "") {
                        if ($Branch -eq "") { throw "-Worktree needs -Branch" }
                        $a["worktree"] = [pscustomobject][ordered]@{ name = $Worktree; branch = $Branch; base = "origin/main" }
                    }
                    $args2 = [pscustomobject]$a
                }
                "close" {
                    if ($SessionId -eq "") { throw "session close needs -SessionId" }
                    # The process to expect is the one the node named when it started the session.
                    $sp = Find-HordeHubSpawn -Dir $actDir -SessionId $SessionId
                    if ($sp.state -ne "known") { throw ("cannot close " + $SessionId + ": " + $sp.reason) }
                    $args2 = New-HordeHubCloseArgs -Spawn $sp.value -Reason $Reason
                    $ct = Resolve-HordeHubCloseTarget -Spawn $sp.value -Node $Node -Entries @(@($pulled) + @($enrolled))
                    if ($ct.state -ne "known") { throw ("cannot close " + $SessionId + ": " + $ct.reason) }
                    $target = "" + $ct.value
                }
                "status" {
                    if ($RequestId -eq "") { throw "session status needs -RequestId" }
                    $args2 = [pscustomobject]@{ requestId = $RequestId }
                    $old = Read-HordeHubActRecord -Dir $actDir -RequestId $RequestId
                    if ($target -eq "" -and $null -ne $old) { $target = "" + $old.deviceId }
                    # A dialled node's request is answered from its own record, which the hub settles -
                    # through request.status itself when an answer was lost (cli/HubCarry.ps1).
                    if ($null -ne $old -and "$(Get-HordeLinkProp $old 'via')" -ceq $script:HordeHubDialledRoute -and ($Node -eq "" -or $Node -ceq "" + $old.deviceId)) { $rec = $old }
                }
            }
            if ($null -eq $rec) {
                if ($target -eq "") { throw ("session " + $Verb + " cannot tell which node to ask: name it with -Node") }
                $tg = Resolve-HordeHubActTarget -Target $target -Pulled $pulled -Enrolled $enrolled
                if ($tg.state -cne "known") { throw ("session " + $Verb + ": " + $tg.reason) }
                $verbName = @{ spawn = "session.spawn"; close = "session.close"; status = "request.status" }[$Verb]
                # A request the contract refuses is refused here, before it is written down or sent.
                $bad = Test-HordeHubActArgs -Contract $contract -Verb $verbName -Arguments $args2
                if ($bad -ne "") { Write-Output ("REFUSED (by the hub, nothing written or sent): the link contract refuses the request: " + $bad); return }
                $via = ""
                # Carried by the hub, never sent from here: the node cannot be dialled. A status is
                # written down too, since it waits for the node's link like any other request.
                if ($tg.value.route -ceq "dialled") { $via = $script:HordeHubDialledRoute }
                $rec = New-HordeHubActRecord -Verb $verbName -DeviceId ("" + $tg.value.deviceId) -Arguments $args2 -Via $via
                if ($via -ne "" -or $verbName -cne "request.status") { Write-HordeHubActRecord -Dir $actDir -Record $rec }
            }
        }

        if ("$(Get-HordeLinkProp $rec 'via')" -ceq $script:HordeHubDialledRoute) {
            # A dialled node: the hub carries it; this waits for the answer the hub writes down.
            $got = Wait-HordeHubCarried -Dir $actDir -RequestId "$($rec.requestId)" -TimeoutMs ($TimeoutSeconds * 1000)
            if ($null -eq $got) { $got = $rec }
            Write-Output (Format-HordeHubCarriedRecord -Record $got)
            if (Test-HordeHubActPending -Record $got) { Write-Output ("ask again with: horde session status -RequestId " + $rec.requestId) }
            return
        }
        $entry = @($pulled | Where-Object { $_.deviceId -ceq "" + $rec.deviceId })
        if ($entry.Count -ne 1) { throw ("the node " + $rec.deviceId + " is no longer registered") }
        $tr = Resolve-HordeLinkTransport -Name $entry[0].transportName
        $resolved = $null; $why = ""
        if ($tr.state -ceq "known") { $resolved = $tr.value } else { $why = "$($tr.reason)" }
        $e = [pscustomobject]@{ deviceId = $entry[0].deviceId; endpoint = $entry[0].endpoint; transport = $resolved; transportError = $why }
        $res = Invoke-HordeHubAct -Entry $e -Hub $hub -Contract $contract -Verb $rec.verb -Arguments $rec.args -RequestId $rec.requestId -IssuedAt $rec.issuedAt -TimeoutMs ($TimeoutSeconds * 1000)
        if ("" + $rec.verb -cne "request.status") {
            $rec.sentAt = @($rec.sentAt) + @(Get-HordeLinkTime)
            if ($res.answered) {
                if ($null -ne $res.error) { $rec.error = $res.error }
                elseif ("" + $res.result.state -ceq "known") { $rec.answer = $res.result.value }
            }
            Write-HordeHubActRecord -Dir $actDir -Record $rec
        }
        Write-Output (Format-HordeHubActAnswer -Res $res -RequestId $rec.requestId)
        if (-not $res.answered -and -not $res.refusedHere) { Write-Output ("send it again with: horde session " + $Verb + " -Resend " + $rec.requestId) }
    }
}
