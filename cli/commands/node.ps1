$HordeCommand = @{
    name    = "node"
    group   = "node"
    # The longest-lived command horde has: each sessions.list builds the projection (11.4 s measured
    # 2026-10-02) and a busy background process is throttled about 7x after 3 s (core/Platform.ps1),
    # which could put a node past the hub's wait (review of PR #81, F2).
    sustained = $true
    usage   = "node serve [-MaxLinks <n>] [-IdleSeconds <s>] [-ReadOnly] [-Messenger <name>] | node init | node rotate-key | node pin -Hub <hub id> -HostKey <key> [-Replace] [-Transport <name>]"
    summary = "serve: answer the hub over the local link: hello, node.info, sessions.list, session.get and request.status, and session.spawn and session.close as this node's policy allows, and messaging (session.deliver, delivery.status, mail.next, mail.receipt) (-ReadOnly: no acts); init, rotate-key, pin: this node's link key and the hub's pinned host key (enrolment, remote plan R17b)"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("serve", "init", "rotate-key", "pin")][string]$Verb,
            # How many links to serve before stopping; 0, the default, serves until stopped.
            [int]$MaxLinks = 0,
            # How long a link may be silent before the node ends it.
            [int]$IdleSeconds = 120,
            # Serve the read verbs only, and refuse every act as unsupported.
            [switch]$ReadOnly,
            # The messenger a deliver goes through (messengers/<name>/), picked by the port's production
            # path; none, or one it refuses, and every deliver is refused with the reason.
            [string]$Messenger = "",
            # pin: the hub's id and host key, as `horde hub init` printed them; -Replace a changed pin.
            [string]$Hub = "",
            [string]$HostKey = "",
            [switch]$Replace,
            # init, rotate-key, pin: which transport's enrolment, when more than one has any.
            [string]$Transport = ""
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ serve = @("MaxLinks", "IdleSeconds", "ReadOnly", "Messenger"); pin = @("Hub", "HostKey", "Replace", "Transport"); init = @("Transport"); "rotate-key" = @("Transport") }
        foreach ($flag in @($PSBoundParameters.Keys)) { if ($flag -ne "Verb" -and $verbFlags[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to node " + $Verb) } }
        if ($Verb -ne "serve") {
            $root = Get-HordeRoot
            foreach ($f in @("Tristate", "Home", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
            . (Join-Path $root "transports\Port.ps1")
            foreach ($t in @(Get-HordeEnrollmentFiles)) { . $t }
            . (Join-Path $root "cli\Enroll.ps1")
            foreach ($l in @(Invoke-HordeNodeEnrollVerb -Verb $Verb -Hub $Hub -HostKey $HostKey -Replace:$Replace -Transport $Transport)) { Write-Output $l }
            return
        }
        # Loaded here, in the command's own scope, so the transports' helpers stay visible to the blocks
        # they register (transports/Port.ps1, the adapter contract).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Projection", "Namespace", "NodeDeliverTo")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "transports\Port.ps1")
        foreach ($t in @(Get-HordeTransportFiles)) { . $t }
        . (Join-Path $root "remote\NodeServe.ps1")
        . (Join-Path $root "remote\Outbox.ps1")
        . (Join-Path $root "cli\NodeServe.ps1")
        . (Join-Path $root "cli\NodeAct.ps1")
        # The messenger port and every messenger, found by folder, loaded in this scope so the blocks they
        # register see their helpers.
        . (Join-Path $root "messengers\Port.ps1")
        foreach ($m in @(Get-HordeMessengerFiles -Root (Join-Path $root "messengers"))) { . $m }
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
        # Not $transport: that is the -Transport parameter (names ignore case), and its [string] type
        # would turn the transport into text (PR #111; tools/ParamShadow.ps1).
        $localTransport = $tr.value
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
        # MESSAGING (R21 slice 4). The message journal and the outbox are this node's own, under its home.
        # remote.deliverTo is read from the node's own layers - engine.json (L1) and engine-live.json (L4),
        # through core/NodeEngineLayers.ps1's Get-HordeNodeEngineLayers, the one reader the spawn path uses - again
        # for every deliver; a layer that fails its checks refuses every deliver and says why. A deliver
        # goes through the messenger port (messengers/Port.ps1) to the messenger -Messenger names, which
        # Resolve-HordeNodeMessenger must accept; with none, every deliver is refused and says why.
        # -ReadOnly builds NO messaging - no messenger, no outbox, no message journal - and the node refuses
        # every verb whose effect is not read (review of #112, B1).
        $messaging = $null
        if (-not $ReadOnly) {
            $messaging = New-HordeNodeMessaging -Root $root -HordeHome $hordeHome -GetView $getView -MessengerName $Messenger
            if ("$($messaging.MessengerError)" -ne "") { Write-Host ("every deliver is refused: " + $messaging.MessengerError) }
        }
        $r = Invoke-HordeNodeServe -Transport $localTransport -Endpoint $node.deviceId -Manifest $manifest -Namespace $ns -GetView $getView -JournalRoot $journalRoot -Act $act -MaxLinks $MaxLinks -IdleTimeoutMs ($IdleSeconds * 1000) -OnListening $say -Messaging $messaging -ReadOnly:$ReadOnly
        Write-Output ("served " + $r.served + " link(s)")
        foreach ($e in $r.endings) { Write-Output ("  " + $e) }
        if ($r.refused -gt 0) { Write-Output ("refused " + $r.refused + " peer(s), the listener kept each time") }
    }
}
