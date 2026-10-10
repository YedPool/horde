$HordeCommand = @{
    name    = "relay"
    group   = "relay"
    # Long-lived like node serve: a watch is a long-poll, and a throttled background process would hold
    # every envelope behind the throttle (core/Platform.ps1).
    sustained = $true
    usage   = "relay run -Relay <name> [-RelayRoot <folder>] [-MaxTurns <n>] | relay stop"
    summary = "run: keep this machine's relay channels moving - the open decisions sent to the founder's phone when they change, his signed answers taken into the decisions list once each, journaled and acked - until stopped (cli/RelayRun.ps1); -Relay names the relay (relays/<name>/), -RelayRoot is the folder of one that keeps its mailboxes on this disk, -MaxTurns stops after that many turns. stop: ask every run on this Horde home to stop after its current turn"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "stop")][string]$Verb,
            [string]$Relay = "",
            [string]$RelayRoot = "",
            [int]$MaxTurns = 0
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ run = @("Relay", "RelayRoot", "MaxTurns"); stop = @() }
        foreach ($flag in @($PSBoundParameters.Keys)) { if ($flag -ne "Verb" -and $verbFlags[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to relay " + $Verb) } }
        # Loaded here, in the command's own scope, so the relays' and channels' helpers stay visible to the
        # blocks they register (relays/Port.ps1 and channels/Port.ps1, the plug-in contracts).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "ModuleSettings")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "channels\Port.ps1")
        . (Join-Path $root "cli\RelayRun.ps1")
        if ($Verb -eq "stop") {
            $path = Request-HordeRelayRunStop
            Write-Output ("asked every relay run on this home to stop after its current turn (" + $path + ")")
            return
        }
        if ($Relay -eq "") { throw "relay run needs -Relay <name>: one of the relays under relays/" }
        if ($MaxTurns -lt 0) { throw "-MaxTurns must be 0 (run until stopped) or more" }
        foreach ($f in @(Get-HordeRelayFiles)) { . $f }
        foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
        $options = @{}
        if ($RelayRoot -ne "") { $options["root"] = [System.IO.Path]::GetFullPath($RelayRoot) }
        $c = Connect-HordeRelay -Name $Relay -Options $options
        if ($c.state -cne "known") { throw ("the relay cannot be reached: " + $c.reason) }
        # Each line as it happens, to the host: the loop's own return value stays its own.
        $r = Invoke-HordeRelayRun -Connection $c.value -MaxTurns $MaxTurns -Say { param($Line) Write-Host $Line }
        if ($r.stoppedBy -ceq "settings") { throw "the relay run did not start: its settings are refused (above)" }
        if ($r.stoppedBy -ceq "locked") { throw "the relay run did not start: another relay run is already running on this home" }
    }
}
