$HordeCommand = @{
    name    = "nodes"
    group   = "hub"
    usage   = "nodes [-Json]"
    summary = "list the hub's nodes from their mirrors: whether each is heard and since when it is not, its sessions and whether its inventory is complete, its clock, and any session listed on two devices"
    run     = {
        [CmdletBinding()] param([switch]$Json)
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        . (Join-Path $root "remote\Mirror.ps1")
        . (Join-Path $root "cli\HubServe.ps1")
        . (Join-Path $root "cli\HubRegistry.ps1")
        $node = Get-HordeNode
        $mirrorRoot = Get-HordeHubMirrorRoot -HomeRoot (Get-HordeHome)
        $contract = Get-HordeLinkContract
        $mirrors = New-Object System.Collections.ArrayList
        # The hub's own node and every node its register holds live: a dialled node is bound by the register.
        foreach ($e in @(Get-HordeHubListedNodes -Own @(Get-HordeHubRegistry -Node $node) -HordeHome (Get-HordeHome))) {
            $m = Read-HordeHubMirror -Path (Get-HordeHubMirrorPath -Root $mirrorRoot -DeviceId $e.deviceId) -DeviceId $e.deviceId -Contract $contract
            # A registered node with no mirror, or one that cannot be read, is shown as never heard:
            # its sessions are unknown, never absent, and the reason says why.
            $mirror = New-HordeNodeMirror -DeviceId $e.deviceId -DeviceName $e.deviceName
            if ($m.state -ceq "known") { $mirror = $m.value }
            elseif ($m.state -ceq "unknown") { $mirror = Set-HordeNodeMirrorLost -Mirror $mirror -At ([datetime]::UtcNow) -Reason $m.reason }
            [void]$mirrors.Add($mirror)
        }
        $report = ConvertTo-HordeNodesReport -Fleet (Get-HordeFleetView -Mirrors $mirrors.ToArray() -Now ([datetime]::UtcNow))
        if ($Json) { Write-Output ($report | ConvertTo-Json -Depth 40 -Compress); return }
        Format-HordeNodesText -Report $report | ForEach-Object { Write-Output $_ }
    }
}
