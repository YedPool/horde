$HordeCommand = @{
    name    = "listen"
    group   = "hub"
    # Runs until stopped, like hub serve: Windows throttles a busy background process about 7x after 3 s
    # (core/Platform.ps1), and the listener is asked whether it still serves every second.
    sustained = $true
    usage   = "listen [-Address <ip>] [-Port <n>] [-AllowFrom <ip,...>] [-Seconds <s>] [-Transport <name>]"
    summary = "accept enrolled nodes' links for as long as it runs, on 127.0.0.1 or one private address of this machine (never a public one): a listener of Horde's own, its every key forced to attach, which relays to this hub's pipe; off loopback it keeps one firewall rule of its own, from the nodes' addresses only, and removes it when it stops"
    run     = {
        [CmdletBinding()] param(
            # The port to listen on; 0, the default, picks a free one and prints it (loopback only: a
            # node on another machine must be told the port).
            [int]$Port = 0,
            # How long to listen; 0, the default, listens until stopped.
            [int]$Seconds = 0,
            # Which transport's listener, when more than one has one.
            [string]$Transport = "",
            # The one address to listen on: 127.0.0.1, the default, or a private address this machine
            # holds - the office LAN, Tailscale, WireGuard. Never a public address or every interface
            # (core/ListenAddress.ps1).
            [string]$Address = "127.0.0.1",
            # Off loopback: the addresses nodes may reach the listener from. None: the enrolled nodes'
            # last-known addresses (horde hub enroll -Address).
            [string[]]$AllowFrom = @()
        )
        # Loaded here, in the command's own scope, so the listeners' helpers stay visible to the blocks
        # they register (transports/Listener.ps1, the adapter contract).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic", "ListenAddress", "FirewallPort")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "cli\HubRegistry.ps1")
        . (Join-Path $root "cli\ListenFirewall.ps1")
        . (Join-Path $root "transports\Listener.ps1")
        foreach ($l in @(Get-HordeListenerFiles)) { . $l }
        if ($Seconds -lt 0) { throw "-Seconds must be 0 (listen until stopped) or more" }
        # THE ADDRESS FIRST (mesh v1, the founder's rule 4): a public address, every interface, a name or an
        # address this machine does not hold is refused before anything else is looked at.
        $where = Resolve-HordeListenAddress -Address $Address
        if ($where.state -cne "known") { throw ("horde listen will not listen there: " + $where.reason) }
        if ($where.value.loopback -and @(@($AllowFrom) | Where-Object { "$_".Trim() -ne "" }).Count -gt 0) { throw "-AllowFrom goes with a network -Address: on loopback no firewall rule is made" }
        $a = Get-HordeListenerAdapter -Name $Transport
        if ($a.state -cne "known") { throw ("no listener to start: " + $a.reason) }
        $hordeHome = Get-HordeHome
        # The hub id is this machine's device id (remote design, decision 1): attach relays to its pipe.
        $hubId = (Get-HordeNode).deviceId
        # Off loopback, the firewall rule before the listener (cli/ListenFirewall.ps1): with nobody to let
        # in, no adapter, or no administrator, nothing listens at all.
        $firewall = New-HordeUnknown -Reason "no firewall is needed on loopback"
        if (-not $where.value.loopback) {
            foreach ($f in @(Get-HordeFirewallFiles -Root $root)) { . $f }
            $firewall = Get-HordeFirewall
        }
        $fwOpen = Open-HordeListenFirewall -Where $where.value -Port $Port -HubId $hubId -Firewall $firewall -AllowFrom $AllowFrom -Known @(Get-HordeHubLiveAddresses -HordeHome $hordeHome) -Root $root -Seconds $Seconds
        if (-not $fwOpen.ok) { throw $fwOpen.reason }
        if ($fwOpen.rule -ne "") { Write-Host $fwOpen.said }
        $why = "stopped"
        $last = ""
        $running = $null
        try {
            # The hub's register (cli/HubRegistry.ps1): a key is served only for a device it holds, live,
            # with that key; read again at every health check.
            $register = { Get-HordeHubLiveKeys -HordeHome $hordeHome }
            $s = Start-HordeListener -Adapter $a.value -HordeHome $hordeHome -HubId $hubId -Root $root -Port $Port -Register $register -Address $where.value.address
            if ($s.state -cne "known") { throw $s.reason }
            $running = $s.value
            try {
                Write-Host ("listening on " + $running.address + " for hub " + $hubId + "; every admitted key is forced to attach")
                $until = $null
                if ($Seconds -gt 0) { $until = [datetime]::UtcNow.AddSeconds($Seconds) }
                while ($null -eq $until -or [datetime]::UtcNow -lt $until) {
                    $h = Test-HordeListenerServing -Running $running
                    if ($h.state -cne "known" -or $h.value -ne $true) {
                        $why = "the listener stopped serving: " + $(if ($h.state -ceq "known") { "it is no longer running" } else { $h.reason })
                        break
                    }
                    Start-Sleep -Milliseconds 1000
                }
            } finally {
                # Ends the server and every session it started, also on Ctrl+C; if this process is killed
                # instead, the job it holds closes and Windows ends them (transports/<name>/Listen.ps1).
                $last = Stop-HordeListener -Running $running
            }
        } finally {
            # The rule goes with the listener, on Ctrl+C too. A killed horde listen leaves it, held to the
            # same nodes and port, and the next horde listen replaces it by its name.
            $closed = Close-HordeListenFirewall -Firewall $firewall -Rule $fwOpen.rule
            if ($closed -ne "") { Write-Host $closed }
        }
        if ($why -cne "stopped") { throw ($why + "; its last words: " + "$last".Trim().Replace("`r", "").Replace("`n", " | ")) }
        Write-Output ("listener on " + $running.address + " stopped")
    }
}
