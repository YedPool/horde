$HordeCommand = @{
    name    = "hub"
    group   = "hub"
    # Long-lived like node serve: a round pulls every node, and a node's sessions.list builds its
    # projection (11.4 s measured 2026-10-02); a busy background process is throttled about 7x after
    # 3 s (core/Platform.ps1), which could put a round past the link's 60 s silence window.
    sustained = $true
    usage   = "hub serve [-Rounds <n>] [-IntervalSeconds <s>] [-Listen] | hub init | hub enroll -Device <id> -Key <key> [-Days <n>] [-Address <node ip>] | hub revoke -Device <id> [-Transport <name>]"
    summary = "serve: pull every registered node's sessions each round into one mirror file per node, read-only on the nodes; init, enroll, revoke: the listener's host key and which node keys it admits (enrolment, remote plan R17b)"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("serve", "init", "enroll", "revoke")][string]$Verb,
            # How many rounds to run before stopping; 0, the default, runs until stopped.
            [int]$Rounds = 0,
            # How long a round waits for the next; 20 s keeps a heard node inside the 60 s window.
            [int]$IntervalSeconds = 20,
            # serve: also take links nodes dial, on the hub pipe, between rounds (remote plan R17c).
            [switch]$Listen,
            # enroll, revoke: the node's device id and, for enroll, its key, as `horde node init` printed them.
            [string]$Device = "",
            [string]$Key = "",
            # enroll: how many days the enrolment lasts (remote design decision 13: one year).
            [int]$Days = 365,
            # enroll: the node's address on the private network it reaches the hub by; horde listen on a
            # network address lets nodes in from these addresses (mesh v1).
            [string]$Address = "",
            # init, enroll, revoke: which transport's enrolment, when more than one has any.
            [string]$Transport = ""
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ serve = @("Rounds", "IntervalSeconds", "Listen"); init = @("Transport"); enroll = @("Device", "Key", "Days", "Transport", "Address"); revoke = @("Device", "Transport") }
        foreach ($flag in @($PSBoundParameters.Keys)) { if ($flag -ne "Verb" -and $verbFlags[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to hub " + $Verb) } }
        if ($Verb -ne "serve") {
            $root = Get-HordeRoot
            foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic", "ListenAddress")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
            . (Join-Path $root "transports\Port.ps1")
            foreach ($t in @(Get-HordeEnrollmentFiles)) { . $t }
            . (Join-Path $root "cli\Enroll.ps1")
            . (Join-Path $root "cli\HubRegistry.ps1")
            foreach ($l in @(Invoke-HordeHubEnrollVerb -Verb $Verb -Root $root -Device $Device -Key $Key -Days $Days -Transport $Transport -Address $Address)) { Write-Output $l }
            return
        }
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
        $listener = $null
        $admit = $null
        if ($Listen) {
            # Only an enrolled device is bound (cli/HubRegistry.ps1): the hub's register and the
            # transport's enrolment must both hold it, live, with one key.
            foreach ($t in @(Get-HordeEnrollmentFiles)) { . $t }
            . (Join-Path $root "cli\Enroll.ps1")
            . (Join-Path $root "cli\HubRegistry.ps1")
            $enrollment = Get-HordeEnrollTransport
            $hubHome = Get-HordeHome
            $admit = { param($DeviceId) Test-HordeHubAdmits -HordeHome $hubHome -DeviceId $DeviceId -Enrollment $enrollment }
            # The hub pipe: the hub's own transport, at the endpoint R17a's attach dials.
            $lt = Resolve-HordeLinkTransport -Name $script:HordeHubOwnTransport
            if ($lt.state -cne "known") { throw ("the hub cannot listen: " + $lt.reason) }
            $l = Start-HordeTransportListener -Transport $lt.value -Endpoint (Get-HordeHubListenEndpoint -HubId $hub.id)
            if ($l.state -cne "known") { throw ("the hub cannot listen for dialled links: " + $l.reason) }
            $listener = $l.value
            Write-Host ("hub listening for dialled links at " + $listener.endpoint)
        }
        try { $done = @(Invoke-HordeHubServe -Nodes $entries -Root $mirrorRoot -Hub $hub -Contract $contract -Rounds $Rounds -IntervalMs ($IntervalSeconds * 1000) -OnRound $say -Listener $listener -Admit $admit) }
        finally { if ($null -ne $listener) { Stop-HordeTransportListener -Listener $listener } }
        Write-Output ("hub ran " + $done.Count + " round(s); mirrors in " + $mirrorRoot)
    }
}
