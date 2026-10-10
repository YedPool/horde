$HordeCommand = @{
    name    = "relay"
    group   = "relay"
    # Long-lived like node serve: a watch is a long-poll, and a throttled background process would hold
    # every envelope behind the throttle (core/Platform.ps1).
    sustained = $true
    usage   = "relay run -Relay <name> [-RelayRoot <folder>] [-MaxTurns <n>] | relay stop | relay pair [-Relay <name>] [-RelayRoot <folder>] [-Label <text>] [-RpId <host>] [-Origin <https://host>] [-InputFile <path>] [-NoPicture] | relay trust list | relay trust revoke <id> [-Reason <text>] | relay identity"
    summary = "run: keep this machine's relay channels moving - the open decisions sent to the founder's phone when they change, his signed answers taken into the decisions list once each, journaled and acked - until stopped (cli/RelayRun.ps1); -Relay names the relay (relays/<name>/), -RelayRoot is the folder of one that keeps its mailboxes on this disk, -MaxTurns stops after that many turns. stop: ask every run on this Horde home to stop after its current turn. pair: pair the founder's phone with this machine (cli/RelayPair.ps1) - make a one-time offer, show it as a QR code (a picture opened here; -NoPicture does not open it) and as text, wait for the phone's response through the relay (-Relay) or pasted here, then ask for the 12-digit number the PHONE shows and compare it; three wrong numbers, or reject, reject the device. -Label is what the device is called here; -RpId and -Origin name the phone app when the relay settings pairRpId and pairOrigin do not; -InputFile reads what would be typed from a file as it grows (for scripts and tests). trust list: every device, peer machine and phone key this machine knows, with its state; trust revoke: end one, by its id, for good. identity: this machine's horde, key ids and mailbox"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "stop", "pair", "trust", "identity")][string]$Verb,
            [Parameter(Position = 1)][string]$Action = "",
            [Parameter(Position = 2)][string]$Id = "",
            [string]$Relay = "",
            [string]$RelayRoot = "",
            [int]$MaxTurns = 0,
            [string]$Label = "",
            [string]$RpId = "",
            [string]$Origin = "",
            [string]$InputFile = "",
            [switch]$NoPicture,
            [string]$Reason = ""
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ run = @("Relay", "RelayRoot", "MaxTurns"); stop = @(); pair = @("Relay", "RelayRoot", "Label", "RpId", "Origin", "InputFile", "NoPicture")
            trust = @("Action", "Id", "Reason"); identity = @() }
        foreach ($flag in @($PSBoundParameters.Keys)) { if ($flag -ne "Verb" -and $verbFlags[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to relay " + $Verb) } }
        # Loaded here, in the command's own scope, so the relays' and channels' helpers stay visible to the
        # blocks they register (relays/Port.ps1 and channels/Port.ps1, the plug-in contracts).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "ModuleSettings")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "channels\Port.ps1")
        if ($Verb -eq "stop") {
            . (Join-Path $root "cli\RelayRun.ps1")
            $path = Request-HordeRelayRunStop
            Write-Output ("asked every relay run on this home to stop after its current turn (" + $path + ")")
            return
        }
        if ($Verb -eq "identity") {
            . (Join-Path $root "cli\RelayPair.ps1")
            $idn = Get-HordeRelayMachineIdentity
            if ($idn.state -cne "known") { throw ("this machine has no relay identity to show: " + $idn.reason) }
            foreach ($l in @(Get-HordeRelayIdentityLines -Identity $idn.value)) { Write-Output $l }
            return
        }
        if ($Verb -eq "trust") {
            . (Join-Path $root "cli\RelayPair.ps1")
            if ($Action -ceq "list") {
                if ($Id -ne "" -or $Reason -ne "") { throw "relay trust list takes nothing more" }
                $t = Get-HordeRelayTrust
                if ($t.state -cne "known") { throw ("the trust store cannot be read: " + $t.reason) }
                foreach ($l in @(Get-HordeRelayTrustLines -Trust $t.value)) { Write-Output $l }
                return
            }
            if ($Action -ceq "revoke") {
                if ($Id -eq "") { throw "relay trust revoke needs the id of a device or machine (relay trust list shows them)" }
                $why = $(if ($Reason -ne "") { $Reason } else { "revoked at the machine with horde relay trust revoke" })
                foreach ($l in @(Invoke-HordeRelayTrustRevoke -Id $Id -Reason $why)) { Write-Output $l }
                return
            }
            throw "relay trust needs list or revoke <id>"
        }
        if ($Action -ne "" -or $Id -ne "") { throw ("relay " + $Verb + " takes no word after it") }
        foreach ($f in @(Get-HordeRelayFiles)) { . $f }
        $c = $null
        if ($Relay -ne "") {
            $options = @{}
            if ($RelayRoot -ne "") { $options["root"] = [System.IO.Path]::GetFullPath($RelayRoot) }
            $made = Connect-HordeRelay -Name $Relay -Options $options
            if ($made.state -cne "known") { throw ("the relay cannot be reached: " + $made.reason) }
            $c = $made.value
        }
        if ($Verb -eq "pair") {
            . (Join-Path $root "cli\QrCode.ps1")
            . (Join-Path $root "cli\RelayPair.ps1")
            $open = $(if ($NoPicture) { $null } else { { param($Path) Start-Process -FilePath $Path } })
            $file = $(if ($InputFile -ne "") { [System.IO.Path]::GetFullPath($InputFile) } else { "" })
            $r = Invoke-HordeRelayPair -Connection $c -RpId $RpId -Origin $Origin -Label $Label -InputFile $file -Say { param($Line) Write-Host $Line } -OpenPicture $open
            if (-not $r.ok) { throw $r.reason }
            return
        }
        . (Join-Path $root "cli\RelayRun.ps1")
        if ($null -eq $c) { throw "relay run needs -Relay <name>: one of the relays under relays/" }
        if ($MaxTurns -lt 0) { throw "-MaxTurns must be 0 (run until stopped) or more" }
        foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
        # Each line as it happens, to the host: the loop's own return value stays its own.
        $r = Invoke-HordeRelayRun -Connection $c -MaxTurns $MaxTurns -Say { param($Line) Write-Host $Line }
        if ($r.stoppedBy -ceq "settings") { throw "the relay run did not start: its settings are refused (above)" }
    }
}
