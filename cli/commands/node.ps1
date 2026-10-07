$HordeCommand = @{
    name    = "node"
    group   = "node"
    # The longest-lived command horde has: each sessions.list builds the projection (11.4 s measured
    # 2026-10-02) and a busy background process is throttled about 7x after 3 s (core/Platform.ps1),
    # which could put a node past the hub's wait (review of PR #81, F2).
    sustained = $true
    usage   = "node serve [-MaxLinks <n>] [-IdleSeconds <s>] [-ReadOnly]"
    summary = "serve this machine's sessions to the hub over the local link: hello, node.info, sessions.list, session.get and request.status, and session.spawn and session.close as this node's policy allows (-ReadOnly: no acts)"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("serve")][string]$Verb,
            # How many links to serve before stopping; 0, the default, serves until stopped.
            [int]$MaxLinks = 0,
            # How long a link may be silent before the node ends it.
            [int]$IdleSeconds = 120,
            # Serve the read verbs only, and refuse every act as unsupported.
            [switch]$ReadOnly
        )
        # Loaded here, in the command's own scope, so the transports' helpers stay visible to the blocks
        # they register (transports/Port.ps1, the adapter contract).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Projection", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        foreach ($t in @(Get-HordeTransportFiles)) { . $t }
        . (Join-Path $root "remote\NodeServe.ps1")
        . (Join-Path $root "cli\NodeServe.ps1")
        . (Join-Path $root "cli\NodeAct.ps1")
        # The act adapters, found by folder (CONTRIBUTING 14), loaded in this scope so the blocks they
        # register see their helpers.
        . (Join-Path $root "core\ReadShared.ps1")
        foreach ($f in @(Get-HordeLaunchAdapterFiles -Root $root)) { . $f }
        foreach ($f in @(Get-HordeHostActorFiles -Root $root)) { . $f }
        if ($MaxLinks -lt 0) { throw "-MaxLinks must be 0 (serve until stopped) or more" }
        if ($IdleSeconds -lt 1) { throw "-IdleSeconds must be at least 1" }
        $node = Get-HordeNode
        $platform = Get-HordeLocalPlatform
        $ns = Get-HordeLocalNamespace -DeviceId $node.deviceId -Platform $platform
        $manifest = New-HordeNodeManifest -Root $root -Node $node -Space $platform.processSpace
        $tr = Resolve-HordeLinkTransport -Name "local"
        if ($tr.state -cne "known") { throw ("this machine cannot serve on the local link: " + $tr.reason) }
        $transport = $tr.value
        $hordeHome = Get-HordeHome
        $journal = Join-Path $hordeHome "node\requests"
        $journalRoot = ""
        $act = $null
        if (-not $ReadOnly) {
            # A node that acts keeps a request journal: an act it could not record could happen twice.
            $journalRoot = Initialize-HordeJournal -Root $journal -Kind "request"
            $ctx = New-HordeNodeActContext -Root $root -HordeHome $hordeHome -Namespace $ns
            Write-Host ("node acts as its policy allows: " + $ctx.note)
            # Records a stopped node left starting are settled before any new act (review of #104, F5).
            foreach ($l in @(Invoke-HordeNodeReconcile -Context $ctx)) { Write-Host ("reconcile: " + $l) }
            $act = { param($a) Invoke-HordeNodeActRequest -Act $a -Context $ctx }
        }
        elseif (Test-Path -LiteralPath $journal -PathType Container) { $journalRoot = $journal }
        # Plain blocks, not closures: a closure runs in a module of its own and would not see the
        # functions loaded above; these run in this scope, where they are.
        $getView = { ConvertTo-HordeSessionViewDocument -Projection (Get-HordeProjection -Platform $platform) }
        $say = { Write-Host ("node " + $node.deviceId + " listening on the local link") }
        $r = Invoke-HordeNodeServe -Transport $transport -Endpoint $node.deviceId -Manifest $manifest -Namespace $ns -GetView $getView -JournalRoot $journalRoot -Act $act -MaxLinks $MaxLinks -IdleTimeoutMs ($IdleSeconds * 1000) -OnListening $say
        Write-Output ("served " + $r.served + " link(s)")
        foreach ($e in $r.endings) { Write-Output ("  " + $e) }
        if ($r.refused -gt 0) { Write-Output ("refused " + $r.refused + " peer(s), the listener kept each time") }
    }
}
