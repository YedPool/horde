$HordeCommand = @{
    name    = "nodes"
    group   = "hub"
    usage   = "nodes [-Json]"
    summary = "list the hub's nodes - its own, and every node in its register of enrolled nodes, which dial in - from their mirrors: whether each is heard and since when it is not, a dialled node's enrolment (live until when, or revoked), its sessions and whether its inventory is complete, its clock, and any session listed on two devices"
    run     = {
        [CmdletBinding()] param([switch]$Json)
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        . (Join-Path $root "remote\Mirror.ps1")
        . (Join-Path $root "cli\HubServe.ps1")
        . (Join-Path $root "cli\HubRegistry.ps1")
        $node = Get-HordeNode
        $hordeHome = Get-HordeHome
        $mirrorRoot = Get-HordeHubMirrorRoot -HomeRoot $hordeHome
        $contract = Get-HordeLinkContract
        # The register is the one source of dialled nodes (remote plan R13b): every device it holds is
        # listed, live or not, beside the hub's own node.
        $enrolled = @(Get-HordeHubEnrolledDevices -HordeHome $hordeHome)
        $entries = New-Object System.Collections.ArrayList
        foreach ($e in @(Get-HordeHubRegistry -Node $node)) { [void]$entries.Add([pscustomobject]@{ deviceId = "" + $e.deviceId; deviceName = "" + $e.deviceName }) }
        foreach ($e in $enrolled) { if (@($entries | Where-Object { $_.deviceId -ceq $e.deviceId }).Count -eq 0) { [void]$entries.Add([pscustomobject]@{ deviceId = "" + $e.deviceId; deviceName = "(dialled)" }) } }
        $mirrors = New-Object System.Collections.ArrayList
        foreach ($e in $entries) {
            $m = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $e.deviceId) -DeviceId $e.deviceId -Contract $contract
            # A registered node with no mirror, or one that cannot be read, is shown as never heard:
            # its sessions are unknown, never absent, and the reason says why.
            $mirror = New-HordeNodeMirror -DeviceId $e.deviceId -DeviceName $e.deviceName
            if ($m.state -ceq "known") { $mirror = $m.value }
            elseif ($m.state -ceq "unknown") { $mirror = Set-HordeNodeMirrorLost -Mirror $mirror -At ([datetime]::UtcNow) -Reason $m.reason }
            [void]$mirrors.Add($mirror)
        }
        $report = ConvertTo-HordeNodesReport -Fleet (Get-HordeFleetView -Mirrors $mirrors.ToArray() -Now ([datetime]::UtcNow)) -Enrolled $enrolled
        if ($Json) { Write-Output ($report | ConvertTo-Json -Depth 40 -Compress); return }
        Format-HordeNodesText -Report $report | ForEach-Object { Write-Output $_ }
    }
}
