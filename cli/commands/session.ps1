$HordeCommand = @{
    name    = "session"
    group   = "hub"
    usage   = "session spawn -Label <L> -Run <runId> -Repo <repoId> -Prompt <text> [-Node <device>] [-Role orc] [-Profile <p>] [-Title <t>] [-Permission <level>] [-Worktree <name> -Branch <b>] [-HostName <h>] | session close -SessionId <id> [-Node <device>] [-Reason <why>] | session status -RequestId <id> [-Node <device>] | any of them -Resend <requestId>"
    summary = "ask a node to start or close a session (remote plan R19): one request per id, written down before it is sent, so a request whose answer was lost is sent again with -Resend and acted on once"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("spawn", "close", "status")][string]$Verb,
            # The node: its device id or name; the hub's own node when not given.
            [string]$Node = "",
            [string]$Label = "", [string]$Role = "orc", [string]$Run = "", [string]$Profile = "claude", [string]$Repo = "",
            [string]$Prompt = "", [string]$Title = "", [string]$Permission = "", [string]$Worktree = "", [string]$Branch = "",
            [string]$HostName = "", [ValidateSet("proof", "routed")][string]$CloseOn = "proof",
            [string]$SessionId = "", [string]$Reason = "closed by the hub", [string]$RequestId = "",
            # Send a request the hub wrote down earlier again, with the same id and issue time.
            [string]$Resend = "",
            [int]$TimeoutSeconds = 240
        )
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        foreach ($t in @(Get-HordeTransportFiles)) { . $t }
        . (Join-Path $root "remote\Protocol.ps1")
        . (Join-Path $root "cli\HubServe.ps1")
        . (Join-Path $root "cli\HubAct.ps1")
        $me = Get-HordeNode
        $version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()
        $hub = [pscustomobject]@{ id = $me.deviceId; name = $me.deviceName; hordeVersion = $version }
        $actDir = Get-HordeHubActDir -HomeRoot (Get-HordeHome)
        $contract = Get-HordeLinkContract

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
                    if ($Label -eq "" -or $Run -eq "" -or $Repo -eq "" -or $Prompt -eq "") { throw "session spawn needs -Label, -Run, -Repo and -Prompt" }
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
                    $ex = $sp.value.answer.expect
                    $args2 = [pscustomobject][ordered]@{ sessionId = $SessionId; expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "" + $ex.ns.device; space = "" + $ex.ns.space }; pid = [long]$ex.pid; procStart = "" + $ex.procStart }; reason = $Reason }
                    if ($target -eq "") { $target = "" + $sp.value.deviceId }
                }
                "status" {
                    if ($RequestId -eq "") { throw "session status needs -RequestId" }
                    $args2 = [pscustomobject]@{ requestId = $RequestId }
                    $old = Read-HordeHubActRecord -Dir $actDir -RequestId $RequestId
                    if ($target -eq "" -and $null -ne $old) { $target = "" + $old.deviceId }
                }
            }
            $entries = @(Get-HordeHubRegistry -Node $me)
            if ($target -eq "") { $target = "" + $me.deviceId }
            $match = @($entries | Where-Object { $_.deviceId -ceq $target -or $_.deviceName -ceq $target })
            if ($match.Count -ne 1) { throw ("the hub has no registered node '" + $target + "'; it knows " + (@($entries | ForEach-Object { $_.deviceName + " (" + $_.deviceId + ")" }) -join ", ")) }
            $verbName = @{ spawn = "session.spawn"; close = "session.close"; status = "request.status" }[$Verb]
            $rec = [pscustomobject][ordered]@{ requestId = (New-HordeLinkFrameId); verb = $verbName; deviceId = "" + $match[0].deviceId; issuedAt = (Get-HordeLinkTime); args = $args2; answer = $null; error = $null; sentAt = @() }
            if ($verbName -cne "request.status") { Write-HordeHubActRecord -Dir $actDir -Record $rec }
        }

        $entry = @(Get-HordeHubRegistry -Node $me | Where-Object { $_.deviceId -ceq "" + $rec.deviceId })
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
        if (-not $res.answered) { Write-Output ("send it again with: horde session " + $Verb + " -Resend " + $rec.requestId) }
    }
}
