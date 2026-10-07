$HordeCommand = @{
    name    = "hub"
    group   = "hub"
    # Long-lived like node serve: a round pulls every node, and a node's sessions.list builds its
    # projection (11.4 s measured 2026-10-02); a busy background process is throttled about 7x after
    # 3 s (core/Platform.ps1), which could put a round past the link's 60 s silence window.
    sustained = $true
    usage   = "hub serve [-Rounds <n>] [-IntervalSeconds <s>]"
    summary = "pull every registered node's sessions over the link each round and keep one mirror file per node; a node it cannot reach has its sessions unknown, never absent. Read-only on the nodes"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("serve")][string]$Verb,
            # How many rounds to run before stopping; 0, the default, runs until stopped.
            [int]$Rounds = 0,
            # How long a round waits for the next; 20 s keeps a heard node inside the 60 s window.
            [int]$IntervalSeconds = 20
        )
        # Loaded here, in the command's own scope, so the transports' helpers stay visible to the blocks
        # they register (transports/Port.ps1, the adapter contract).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        foreach ($t in @(Get-HordeTransportFiles)) { . $t }
        . (Join-Path $root "remote\Mirror.ps1")
        . (Join-Path $root "cli\HubServe.ps1")
        if ($Rounds -lt 0) { throw "-Rounds must be 0 (run until stopped) or more" }
        if ($IntervalSeconds -lt 1) { throw "-IntervalSeconds must be at least 1" }
        $node = Get-HordeNode
        $version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()
        # The hub is a node too, so it says hello under its own device id (remote design, decision 1).
        $hub = [pscustomobject]@{ id = $node.deviceId; name = $node.deviceName; hordeVersion = $version }
        $entries = @(Get-HordeHubRegistry -Node $node | ForEach-Object {
            $tr = Resolve-HordeLinkTransport -Name $_.transportName
            $resolved = $null
            $why = ""
            if ($tr.state -ceq "known") { $resolved = $tr.value } else { $why = "$($tr.reason)" }
            [pscustomobject]@{ deviceId = $_.deviceId; deviceName = $_.deviceName; endpoint = $_.endpoint; transport = $resolved; transportError = $why }
        })
        $mirrorRoot = Get-HordeHubMirrorRoot -HomeRoot (Get-HordeHome)
        $contract = Get-HordeLinkContract
        # Write-Host, not Write-Output: the block runs inside the loop, whose output is its rounds.
        $say = { param($Round) foreach ($o in $Round.outcomes) { Write-Host ($Round.at + " " + $o) } }
        $done = @(Invoke-HordeHubServe -Nodes $entries -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds $Rounds -IntervalMs ($IntervalSeconds * 1000) -OnRound $say)
        Write-Output ("hub ran " + $done.Count + " round(s); mirrors in " + $mirrorRoot)
    }
}
